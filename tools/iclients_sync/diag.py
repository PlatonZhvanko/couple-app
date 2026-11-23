import sys, os, requests
sys.path.insert(0, "tools/iclients_sync")
from datetime import datetime, timezone, timedelta
import sync

today = datetime.now(timezone.utc).date()
rid = sync.resource_instance_id()
recs = [x for x in sync.iclients_records(today - timedelta(days=7), today + timedelta(days=10))
        if any(i.get("id") == rid for i in x.get("resource_instances") or [])]
print("всего записей ресурса:", len(recs))
for x in recs:
    c = x.get("client") or {}
    name = c.get("display_name") or c.get("name") or ""
    low = name.lower()
    mark = "СШ" in name.upper() or "школ" in low
    print(x["datetime"][:16], "act", x.get("activity_id"), "del", x.get("deleted"),
          "client:", name if mark else f"<{len(name)} симв>",
          "| services:", [s.get("title") for s in x.get("services") or []] if mark or x.get("activity_id") else "-",
          "| comment:", (x.get("comment") or "")[:40] if mark else "-", "| clients_count", x.get("clients_count"))
base = os.environ["SUPABASE_URL"].rstrip("/") + "/rest/v1"
k = os.environ["SUPABASE_SERVICE_KEY"]
h = {"apikey": k, "Authorization": f"Bearer {k}"}
rows = requests.get(f"{base}/records?select=id,kind,payload&kind=eq.planner.event&limit=1000", headers=h, timeout=30).json()
for r in rows:
    p = r.get("payload") or {}
    t = p.get("title") or ""
    if "СШ" in t.upper():
        print("EVENT", r["id"][:8], repr(t[:60]), "src", p.get("source"), "scope", p.get("scope"), "notes", repr((p.get("notes") or "")[:40]), "start", p.get("start"), "rep", p.get("repeatRule"))
