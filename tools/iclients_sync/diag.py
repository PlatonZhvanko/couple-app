import os, requests
base = os.environ["SUPABASE_URL"].rstrip("/") + "/rest/v1"
k = os.environ["SUPABASE_SERVICE_KEY"]
h = {"apikey": k, "Authorization": f"Bearer {k}"}
rows = requests.get(f"{base}/records?select=id,payload,updated_at,deleted_at&kind=eq.planner.event&order=updated_at.desc&limit=200", headers=h, timeout=30).json()
for r in rows:
    p = r.get("payload") or {}
    if p.get("source") == "yclients":
        print(r["id"][:8], "upd", r["updated_at"], "del", r["deleted_at"], "start", p.get("start"), "notes", p.get("notes"), "v", p.get("v"), "canc", p.get("cancelledDays"))
