// Загрузчик синхронизации YClients. Его вставляют в Supabase один раз.
// Каждый запуск он скачивает свежую логику (logic.js) из репозитория и выполняет её,
// поэтому правки приходят без ручной вставки кода. Секреты YClients лежат в настройках функции.

const LOGIC_URL = "https://raw.githubusercontent.com/PlatonZhvanko/couple-app/main/supabase/functions/yclients-sync/logic.js";

Deno.serve(async (req: Request) => {
  // Полную синхронизацию запускает только расписание Supabase: у него есть общий секрет.
  // Приложение (вошедший пользователь) может лишь прочитать расписание Олимпика за день.
  const secret = (Deno.env.get("CRON_SECRET") ?? "").trim();
  const isCron = !!secret && req.headers.get("x-cron-secret") === secret;
  let mode = "sync";
  let arg = "";
  if (!isCron) {
    const auth = req.headers.get("authorization") ?? "";
    const who = auth.startsWith("Bearer eyJ")
      ? await fetch(`${Deno.env.get("SUPABASE_URL")}/auth/v1/user`, {
        headers: { Authorization: auth, apikey: Deno.env.get("SUPABASE_ANON_KEY") ?? "" },
      })
      : null;
    if (!who || !who.ok) return new Response("forbidden", { status: 403 });
    const body = await req.json().catch(() => ({}));
    if (body.action !== "olimpic") return new Response("forbidden", { status: 403 });
    mode = "olimpic";
    arg = String(body.day ?? "");
  }
  try {
    const r = await fetch(`${LOGIC_URL}?t=${Date.now()}`, { cache: "no-store" });
    if (!r.ok) throw new Error(`не удалось скачать логику: ${r.status}`);
    const code = await r.text();
    const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
    const run = new AsyncFunction("mode", "arg", `${code}\nreturn mode === "olimpic" ? await olimpicLive(arg) : await sync();`);
    return new Response(String(await run(mode, arg)));
  } catch (e) {
    return new Response(`Ошибка: ${(e as Error).message}`, { status: 500 });
  }
});
