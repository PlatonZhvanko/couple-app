-- Запуск синхронизации YClients каждые 5 минут из самого Supabase.
-- Перед запуском: Database -> Extensions -> включить pg_cron и pg_net.
-- Замени ПРИДУМАЙ-ПАРОЛЬ на тот же пароль, что в секрете CRON_SECRET функции yclients-sync.

select cron.schedule(
  'yclients-sync',
  '*/5 * * * *',
  $$
  select net.http_post(
    url := 'https://izyhshljamzgyzxoupss.supabase.co/functions/v1/yclients-sync',
    headers := '{"Content-Type": "application/json", "x-cron-secret": "ПРИДУМАЙ-ПАРОЛЬ"}'::jsonb,
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
  $$
);
