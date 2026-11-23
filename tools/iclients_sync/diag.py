import os, requests
base = os.environ["SUPABASE_URL"].rstrip("/") + "/rest/v1"
k = os.environ["SUPABASE_SERVICE_KEY"]
h = {"apikey": k, "Authorization": f"Bearer {k}"}
rows = requests.get(f"{base}/records?select=id,kind,payload,updated_at,deleted_at,server_updated_at&order=server_updated_at.desc&limit=25", headers=h, timeout=30).json()
for r in rows:
    p = r.get("payload") or {}
    print(r["kind"], r["id"][:8], "src", p.get("source"), "scope", p.get("scope"), "upd", r["updated_at"], "srv", r["server_updated_at"], "DEL", r["deleted_at"])
