"""Подтягивает записи Насти из журнала iClients в приложение «Вдвоём».

Запускается по расписанию (см. .github/workflows/iclients-sync.yml):
1. читает журнал iClients (API YCLIENTS) за ближайшие недели;
2. берёт записи, где выбран ресурс «Новик Анастасия»;
3. кладёт их в таблицу `records` в Supabase как записи клиентов и клиентов Насти.
Приложение само подтягивает их при обычной синхронизации.

Секреты (токены) берутся только из переменных окружения, в коде их нет.
"""
from __future__ import annotations

import os
import re
import sys
import uuid
from datetime import date, datetime, timedelta, timezone

import requests

API_BASE = "https://api.yclients.com/api/v1"
PAGE = 100
# Экземпляр ресурса «Новик Анастасия» в iClients.
RESOURCE_TITLE = "Новик Анастасия"
MEMBER = "partner"
NS = uuid.UUID("6f1c2b0e-5a3d-4c57-9a52-1c1e5a7d0001")
DAYS_BACK = 1
DAYS_AHEAD = 60

http = requests.Session()


def norm(name: str) -> str:
    """Имя для сравнения: без регистра, «ё»=«е», дефисы и точки как пробелы."""
    name = name.lower().replace("ё", "е")
    for ch in "-–—_.,":
        name = name.replace(ch, " ")
    return " ".join(name.split())


def is_excluded(name: str) -> bool:
    n = norm(name)
    return any(n == e or n.startswith(e + " ") for e in EXCLUDED)


# Клиенты, чьи записи не переносим (имена через запятую, регистр не важен).
EXCLUDED = {norm(n) for n in os.environ.get("ICLIENTS_EXCLUDE_CLIENTS", "").split(",") if n.strip()}


def env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        sys.exit(f"Не задан секрет {name}")
    return value


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def iclients_records(start: date, end: date) -> list[dict]:
    headers = {
        "Authorization": f"Bearer {env('YCLIENTS_PARTNER_TOKEN')}, User {env('YCLIENTS_USER_TOKEN')}",
        "Accept": "application/vnd.api.v2+json",
    }
    url = f"{API_BASE}/records/{env('YCLIENTS_COMPANY_ID')}"
    out: list[dict] = []
    page = 1
    while True:
        r = http.get(url, headers=headers, timeout=30, params={
            "start_date": start.isoformat(), "end_date": end.isoformat(), "page": page, "count": PAGE})
        r.raise_for_status()
        body = r.json()
        if not body.get("success"):
            raise RuntimeError(f"iClients: {(body.get('meta') or {}).get('message')}")
        batch = body.get("data") or []
        out.extend(batch)
        if len(batch) < PAGE:
            return out
        page += 1


def resource_instance_id() -> int:
    """Id ресурса, который в iClients называется ровно «Новик Анастасия»."""
    headers = {
        "Authorization": f"Bearer {env('YCLIENTS_PARTNER_TOKEN')}, User {env('YCLIENTS_USER_TOKEN')}",
        "Accept": "application/vnd.api.v2+json",
    }
    r = http.get(f"{API_BASE}/resources/{env('YCLIENTS_COMPANY_ID')}", headers=headers, timeout=30)
    r.raise_for_status()
    found = [inst["id"] for res in r.json().get("data") or []
             for inst in res.get("instances") or [] if (inst.get("title") or "").strip() == RESOURCE_TITLE]
    if len(found) != 1:
        sys.exit(f"Ресурс «{RESOURCE_TITLE}» найден {len(found)} раз, ожидался один")
    return found[0]


class Supabase:
    def __init__(self) -> None:
        self.base = env("SUPABASE_URL").rstrip("/") + "/rest/v1"
        key = env("SUPABASE_SERVICE_KEY")
        self.headers = {"apikey": key, "Authorization": f"Bearer {key}"}

    def get(self, table: str, query: str) -> list[dict]:
        rows: list[dict] = []
        offset = 0
        while True:
            r = http.get(f"{self.base}/{table}?{query}&limit=1000&offset={offset}", headers=self.headers, timeout=30)
            r.raise_for_status()
            batch = r.json()
            rows.extend(batch)
            if len(batch) < 1000:
                return rows
            offset += 1000

    def upsert(self, rows: list[dict]) -> None:
        for i in range(0, len(rows), 200):
            r = http.post(
                f"{self.base}/records?on_conflict=id",
                headers={**self.headers, "Content-Type": "application/json",
                         "Prefer": "resolution=merge-duplicates,return=minimal"},
                json=rows[i:i + 200], timeout=60)
            r.raise_for_status()


def digits(phone: str) -> str:
    d = re.sub(r"\D", "", phone or "")
    return d[-10:] if len(d) >= 10 else d


def main() -> None:
    if not os.environ.get("SUPABASE_SERVICE_KEY", "").strip():
        print("Секреты ещё не добавлены, пропускаю")
        return
    today = datetime.now(timezone.utc).date()
    start, end = today - timedelta(days=DAYS_BACK), today + timedelta(days=DAYS_AHEAD)
    resource_id = resource_instance_id()
    fetched = [
        r for r in iclients_records(start, end)
        if not r.get("activity_id")
        and any(i.get("id") == resource_id for i in r.get("resource_instances") or [])
        and not is_excluded((r.get("client") or {}).get("display_name") or (r.get("client") or {}).get("name") or "")
    ]

    db = Supabase()
    members = db.get("couple_members", f"select=couple_id&role=eq.{MEMBER}")
    if not members:
        sys.exit("В базе нет участника «partner»")
    couple_id = members[0]["couple_id"]

    existing = {
        r["id"]: r for r in db.get("records", "select=id,kind,payload,deleted_at&kind=in.(clients.client,clients.appointment)")
    }
    now = iso(datetime.now(timezone.utc))
    rows: list[dict] = []

    # --- клиенты ---
    my_clients = [r for r in existing.values()
                  if r["kind"] == "clients.client" and not r["deleted_at"]
                  and (r["payload"] or {}).get("member") == MEMBER]
    by_phone = {digits(r["payload"].get("phone", "")): r["id"] for r in my_clients if digits(r["payload"].get("phone", ""))}
    client_ids: dict[int, str] = {}
    for rec in fetched:
        c = rec.get("client") or {}
        cid = c.get("id")
        if not cid or cid in client_ids:
            continue
        det_id = str(uuid.uuid5(NS, f"client:{cid}"))
        phone = c.get("phone") or ""
        if det_id in existing:
            client_ids[cid] = det_id
        elif digits(phone) and digits(phone) in by_phone:
            client_ids[cid] = by_phone[digits(phone)]
        else:
            client_ids[cid] = det_id
            rows.append({
                "id": det_id, "couple_id": couple_id, "kind": "clients.client", "updated_at": now, "deleted_at": None,
                "payload": {"name": c.get("display_name") or c.get("name") or "Клиент iClients",
                            "phone": phone, "note": "", "member": MEMBER, "createdAt": now, "source": "iclients"},
            })

    # --- записи ---
    seen: set[str] = set()
    for rec in fetched:
        rid = str(uuid.uuid5(NS, f"record:{rec['id']}"))
        seen.add(rid)
        begin = datetime.fromisoformat(rec["datetime"])
        services = rec.get("services") or []
        wanted = {
            "clientID": client_ids.get((rec.get("client") or {}).get("id")),
            "service": ", ".join(s.get("title", "") for s in services if s.get("title")),
            "start": iso(begin),
            "durationMinutes": max(1, round((rec.get("seance_length") or 3600) / 60)),
            "price": float(sum((s.get("cost") or s.get("first_cost") or 0) for s in services)),
            "note": rec.get("comment") or "",
        }
        cancelled = bool(rec.get("deleted")) or rec.get("attendance") == -1
        old = existing.get(rid)
        if old is None:
            payload = {**wanted, "status": "cancelled" if cancelled else "planned",
                       "reminderMinutes": 60, "member": MEMBER, "source": "iclients"}
        else:
            payload = dict(old["payload"] or {})
            before = dict(payload)
            for k in ("clientID", "service", "start", "durationMinutes"):
                if wanted[k] is not None:
                    payload[k] = wanted[k]
            if not payload.get("price"):
                payload["price"] = wanted["price"]
            if cancelled:
                payload["status"] = "cancelled"
            if payload == before and not old["deleted_at"]:
                continue
        rows.append({"id": rid, "couple_id": couple_id, "kind": "clients.appointment",
                     "updated_at": now, "deleted_at": None, "payload": payload})

    # Запись была в приложении, а из журнала пропала -> отмена.
    for rid, old in existing.items():
        p = old["payload"] or {}
        if (old["kind"] == "clients.appointment" and p.get("source") == "iclients" and rid not in seen
                and not old["deleted_at"] and p.get("status") == "planned"
                and p.get("start", "") >= iso(datetime.combine(start, datetime.min.time(), timezone.utc))):
            rows.append({"id": rid, "couple_id": couple_id, "kind": "clients.appointment",
                         "updated_at": now, "deleted_at": None, "payload": {**p, "status": "cancelled"}})

    if rows:
        db.upsert(rows)
    print(f"Записей в iClients: {len(fetched)}, обновлено в приложении: {len(rows)}")


if __name__ == "__main__":
    main()
