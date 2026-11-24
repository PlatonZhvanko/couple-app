import os, requests
base = os.environ["SUPABASE_URL"].rstrip("/") + "/rest/v1"
k = os.environ["SUPABASE_SERVICE_KEY"]
h = {"apikey": k, "Authorization": f"Bearer {k}"}
rows = requests.get(f"{base}/records?select=id,payload,updated_at&kind=eq.sys.heartbeat", headers=h, timeout=30).json()
print("HEARTBEAT", rows)
# 1795515783
# 1795516263
