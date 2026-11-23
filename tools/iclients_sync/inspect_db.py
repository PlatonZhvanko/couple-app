"""Диагностика: показывает, какие записи YClients лежат в базе (без имён и телефонов)."""
import os
import sys

import requests

base = os.environ["SUPABASE_URL"].rstrip("/") + "/rest/v1"
key = os.environ["SUPABASE_SERVICE_KEY"]
h = {"apikey": key, "Authorization": f"Bearer {key}"}
rows = requests.get(
    f"{base}/records?select=id,kind,payload,deleted_at,updated_at,server_updated_at"
    "&kind=in.(planner.event,clients.appointment)&order=server_updated_at.desc&limit=60",
    headers=h, timeout=30)
rows.raise_for_status()
for r in rows.json():
    p = r["payload"] or {}
    if r["kind"] == "planner.event" and p.get("source") != "yclients" and p.get("createdBy") != "partner":
        continue
    print(r["kind"], r["id"][:8], "deleted" if r["deleted_at"] else "live",
          "source=", p.get("source"), "scope=", p.get("scope"), "cat=", p.get("category"),
          "createdBy=", p.get("createdBy"), "start=", p.get("start"), "end=", p.get("end"),
          "participants=", len(p.get("participantIDs") or []), "keys=", sorted(p.keys()),
          "upd=", r["updated_at"], "srv=", r["server_updated_at"])
