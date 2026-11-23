import sys
sys.path.insert(0, "tools/iclients_sync")
from datetime import datetime, timezone, timedelta
import sync

today = datetime.now(timezone.utc).date()
rid = sync.resource_instance_id()
headers = {"Authorization": f"Bearer {sync.env('YCLIENTS_PARTNER_TOKEN')}, User {sync.env('YCLIENTS_USER_TOKEN')}",
           "Accept": "application/vnd.api.v2+json"}
r = sync.http.get(f"{sync.API_BASE}/resources/{sync.env('YCLIENTS_COMPANY_ID')}", headers=headers, timeout=30)
for res in r.json().get("data") or []:
    print("RESOURCE", res.get("id"), res.get("title"), [(i.get("id"), i.get("title")) for i in res.get("instances") or []])
recs = [x for x in sync.iclients_records(today, today + timedelta(days=7))
        if any(i.get("id") == rid for i in x.get("resource_instances") or [])]
for x in recs[:3]:
    print("REC keys", sorted(x.keys()))
    print("  resource_instances", x.get("resource_instances"))
    print("  staff", (x.get("staff") or {}).get("name"), "comment", repr(x.get("comment"))[:60])
    print("  services", [s.get("title") for s in x.get("services") or []])
    print("  custom", x.get("custom_fields"), x.get("record_labels"))
