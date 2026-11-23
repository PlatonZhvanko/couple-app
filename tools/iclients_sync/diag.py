import os, requests
base = os.environ["SUPABASE_URL"].rstrip("/") + "/rest/v1"
k = os.environ["SUPABASE_SERVICE_KEY"]
h = {"apikey": k, "Authorization": f"Bearer {k}"}
rows = requests.get(f"{base}/records?select=id,kind,payload,updated_at,deleted_at&kind=in.(planner.event,clients.appointment)&order=updated_at.desc&limit=300", headers=h, timeout=30).json()
for r in rows:
    p = r.get("payload") or {}
    if p.get("source") in ("yclients", "iclients"):
        print(r["kind"], r["id"][:8], "src", p.get("source"), "upd", r["updated_at"], "DEL", r["deleted_at"], "start", p.get("start") or p.get("startsAt"), "v", p.get("v"))
