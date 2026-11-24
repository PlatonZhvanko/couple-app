// Загрузчик синхронизации YClients. Его вставляют в Supabase один раз.
// Каждый запуск он скачивает свежую логику (logic.js) из репозитория и выполняет её,
// поэтому правки приходят без ручной вставки кода. Секреты YClients лежат в настройках функции.

const LOGIC_URL = "https://raw.githubusercontent.com/PlatonZhvanko/couple-app/main/supabase/functions/yclients-sync/logic.js";

Deno.serve(async (req: Request) => {
  // Запускать может только расписание Supabase: у него есть общий секрет.
  const secret = (Deno.env.get("CRON_SECRET") ?? "").trim();
  if (!secret || req.headers.get("x-cron-secret") !== secret) {
    return new Response("forbidden", { status: 403 });
  }
  try {
    const r = await fetch(`${LOGIC_URL}?t=${Date.now()}`, { cache: "no-store" });
    if (!r.ok) throw new Error(`не удалось скачать логику: ${r.status}`);
    const code = await r.text();
    const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
    const run = new AsyncFunction(`${code}\nreturn await sync();`);
    return new Response(String(await run()));
  } catch (e) {
    return new Response(`Ошибка: ${(e as Error).message}`, { status: 500 });
  }
});
