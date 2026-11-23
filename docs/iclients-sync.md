# Синхронизация YClients → планер Насти

Раз в 10 минут GitHub Actions (`.github/workflows/iclients-sync.yml`) запускает
`tools/iclients_sync/sync.py`. Он читает журнал YClients, берёт записи с ресурсом
«Новик Анастасия» (id 261720) и кладёт их в Supabase (`records`) как
`planner.event` (тренировка с клиентом в планере) и `clients.client` с `member = partner`, `source = yclients` у записи.

Секреты (GitHub → Settings → Secrets and variables → Actions):
`YCLIENTS_COMPANY_ID`, `YCLIENTS_PARTNER_TOKEN`, `YCLIENTS_USER_TOKEN`,
`SUPABASE_URL`, `SUPABASE_SERVICE_KEY` (секретный ключ Supabase, не anon).

Правила: статусы «пришёл/не пришёл» не синхронизируются (оплату и статусы Настя отмечает сама);
время и длительность подтягиваются (перенос, удлинение, сокращение); если запись удалена в YClients
и Настя ещё не отметила её статус, она становится «Отмена»; клиенты ищутся по телефону, иначе создаются.

## Автозапуск из Supabase (основной)

GitHub по расписанию запускал синхронизацию ненадёжно, поэтому основной запуск идёт из Supabase:
функция `supabase/functions/yclients-sync/index.ts` (то же, что `sync.py`) и расписание
`supabase/schedule-sync.sql` (pg_cron каждые 5 минут). Секреты функции: `YCLIENTS_COMPANY_ID`,
`YCLIENTS_PARTNER_TOKEN`, `YCLIENTS_USER_TOKEN`, `CRON_SECRET` (общий пароль с расписанием).
Ключ базы функция получает от Supabase сама. GitHub-запуск остаётся запасным ручным.
