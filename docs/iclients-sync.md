# Синхронизация iClients → планер Насти

Раз в 10 минут GitHub Actions (`.github/workflows/iclients-sync.yml`) запускает
`tools/iclients_sync/sync.py`. Он читает журнал iClients, берёт записи с ресурсом
«Новик Анастасия» (id 261720) и кладёт их в Supabase (`records`) как
`clients.appointment` и `clients.client` с `member = partner`, `source = iclients`.

Секреты (GitHub → Settings → Secrets and variables → Actions):
`YCLIENTS_COMPANY_ID`, `YCLIENTS_PARTNER_TOKEN`, `YCLIENTS_USER_TOKEN`,
`SUPABASE_URL`, `SUPABASE_SERVICE_KEY` (секретный ключ Supabase, не anon).

Правила: «не пришёл»/удалена/пропала из журнала → «Отмена»; время и длительность
берутся из iClients; клиенты ищутся по телефону, иначе создаются.
