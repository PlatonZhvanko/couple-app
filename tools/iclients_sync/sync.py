"""Подтягивает записи Насти из журнала YClients в приложение «Вдвоём».

Запускается по расписанию (см. .github/workflows/iclients-sync.yml):
1. читает журнал YClients (API YCLIENTS) за ближайшие недели;
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
from zoneinfo import ZoneInfo

API_BASE = "https://api.yclients.com/api/v1"
PAGE = 100
# Экземпляр ресурса «Новик Анастасия» в YClients.
RESOURCE_TITLE = "Новик Анастасия"
MEMBER = "partner"
MOSCOW = ZoneInfo("Europe/Moscow")
SCHEMA_VERSION = 2
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
            raise RuntimeError(f"YClients: {(body.get('meta') or {}).get('message')}")
        batch = body.get("data") or []
        out.extend(batch)
        if len(batch) < PAGE:
            return out
        page += 1


def resource_instance_id() -> int:
    """Id ресурса, который в YClients называется ровно «Новик Анастасия»."""
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


def day_key(moment: datetime) -> str:
    """Ключ дня отмены: начало московского дня в секундах (как в приложении)."""
    day = moment.astimezone(MOSCOW).replace(hour=0, minute=0, second=0, microsecond=0)
    return str(int(day.timestamp()))


def apply_no_show(payload: dict, rec: dict, begin: datetime) -> None:
    """«Не пришёл» в YClients = отмена в приложении. Если статус сменился обратно,
    возвращаем запись, но только если отмену поставили мы и Настя ничего не отмечала."""
    if payload.get("statuses") or payload.get("partnerStatuses"):
        return
    key = day_key(begin)
    keys = [k for k in (payload.get("cancelledDays") or "").split(",") if k]
    no_show = rec.get("attendance") == -1 or rec.get("visit_attendance") == -1
    if no_show and key not in keys:
        payload["cancelledDays"] = ",".join(keys + [key])
        payload["ycCancelled"] = True
    elif not no_show and payload.get("ycCancelled") and key in keys:
        keys.remove(key)
        payload["cancelledDays"] = ",".join(keys)
        payload["ycCancelled"] = False


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
        r["id"]: r for r in db.get("records", "select=id,kind,payload,deleted_at&kind=in.(clients.client,clients.appointment,planner.event)")
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
                "payload": {"name": c.get("display_name") or c.get("name") or "Клиент YClients",
                            "phone": phone, "note": "", "member": MEMBER, "createdAt": now, "source": "iclients"},
            })

    # --- записи: появляются в планере Насти как её тренировки с клиентом ---
    seen: set[str] = set()
    for rec in fetched:
        rid = str(uuid.uuid5(NS, f"event:{rec['id']}"))
        seen.add(rid)
        begin = datetime.fromisoformat(rec["datetime"])
        finish = begin + timedelta(seconds=rec.get("seance_length") or 3600)
        client = rec.get("client") or {}
        client_uuid = client_ids.get(client.get("id"))
        services = ", ".join(s.get("title", "") for s in rec.get("services") or [] if s.get("title"))
        # Вместо названия услуги показываем корт: в YClients он записан как «сотрудник» записи.
        court = ((rec.get("staff") or {}).get("name") or "").strip() or services
        old = existing.get(rid)
        before: dict = {}
        if old is None:
            payload = {
                "title": client.get("display_name") or client.get("name") or "Запись YClients",
                "notes": court, "start": iso(begin), "end": iso(finish), "isAllDay": False,
                "scope": MEMBER, "category": "personal", "repeatRule": "none",
                "reminderMinutes": 60, "createdBy": MEMBER, "createdAt": now,
                "participantIDs": [client_uuid.upper()] if client_uuid else [],
                "isPrivate": False, "repeatInterval": 1, "source": "yclients", "v": SCHEMA_VERSION,
            }
        else:
            # Меняем только время: остальное (оплата, статусы, заметки) ведёт Настя.
            payload = dict(old["payload"] or {})
            before = dict(payload)
            payload["start"], payload["end"] = iso(begin), iso(finish)
            payload["notes"] = court
            # Версия формата: при её повышении запись обновляется заново, и телефоны, которые
            # успели получить её старой версией приложения, подтягивают её ещё раз.
            payload["v"] = SCHEMA_VERSION
        apply_no_show(payload, rec, begin)
        if old is not None and payload == before and not old["deleted_at"]:
            continue
        rows.append({"id": rid, "couple_id": couple_id, "kind": "planner.event",
                     "updated_at": now, "deleted_at": None, "payload": payload})

    # Запись пропала из журнала (удалена): отменяем занятие, если Настя не отметила статус.
    window_start = iso(datetime.combine(start, datetime.min.time(), timezone.utc))
    for rid, old in existing.items():
        p = old["payload"] or {}
        if (old["kind"] == "planner.event" and p.get("source") == "yclients" and rid not in seen
                and not old["deleted_at"] and not p.get("statuses") and not p.get("partnerStatuses")
                and p.get("start", "") >= window_start):
            day = datetime.fromisoformat(p["start"].replace("Z", "+00:00")).astimezone(MOSCOW)
            key = str(int(day.replace(hour=0, minute=0, second=0, microsecond=0).timestamp()))
            keys = [k for k in (p.get("cancelledDays") or "").split(",") if k]
            if key in keys:
                continue
            rows.append({"id": rid, "couple_id": couple_id, "kind": "planner.event", "updated_at": now,
                         "deleted_at": None, "payload": {**p, "cancelledDays": ",".join(keys + [key])}})

    # Первые версии клали записи в «Клиенты» (clients.appointment): убираем их, теперь есть записи планера.
    for rid, old in existing.items():
        p = old["payload"] or {}
        if old["kind"] == "clients.appointment" and p.get("source") == "iclients" and not old["deleted_at"]:
            rows.append({"id": rid, "couple_id": couple_id, "kind": "clients.appointment",
                         "updated_at": now, "deleted_at": now, "payload": p})

    if rows:
        db.upsert(rows)
    print(f"Записей в YClients: {len(fetched)}, обновлено в приложении: {len(rows)}")


if __name__ == "__main__":
    main()
