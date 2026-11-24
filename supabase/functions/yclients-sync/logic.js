// Синхронизация записей Насти из YClients в приложение «Вдвоём».
// Логика синхронизации. Её собирает в logic.js (см. build.sh) и запускает загрузчик index.ts.
// Секреты YClients берутся из настроек функции, в коде их нет.
const API_BASE = "https://api.yclients.com/api/v1";
const PAGE = 100;
const RESOURCE_TITLE = "Новик Анастасия";
const MEMBER = "partner";
const SCHEMA_VERSION = 2;
const NS = "6f1c2b0e-5a3d-4c57-9a52-1c1e5a7d0001";
const DAYS_BACK = 1;
const DAYS_AHEAD = 60;
const MSK = 3 * 3600 * 1000; // Москва: UTC+3 без перехода на летнее время
function env(name) {
    const v = (Deno.env.get(name) ?? "").trim();
    if (!v)
        throw new Error(`Не задан секрет ${name}`);
    return v;
}
function norm(name) {
    let n = name.toLowerCase().replaceAll("ё", "е");
    for (const ch of "-–—_.,")
        n = n.replaceAll(ch, " ");
    return n.split(/\s+/).filter(Boolean).join(" ");
}
function isExcluded(name, excluded) {
    const n = norm(name);
    return excluded.some((e) => n === e || n.startsWith(e + " "));
}
function iso(d) {
    return d.toISOString().replace(/\.\d{3}Z$/, "Z");
}
function nameKey(name) {
    return (name ?? "").toLowerCase().replaceAll("ё", "е").split(/\s+/).filter(Boolean).join(" ");
}
function digits(phone) {
    const d = (phone ?? "").replace(/\D/g, "");
    return d.length >= 10 ? d.slice(-10) : d;
}
// uuid5 как в Python (uuid.uuid5), чтобы id записей совпадали со старой синхронизацией.
async function uuid5(name) {
    const ns = NS.replaceAll("-", "").match(/../g).map((h) => parseInt(h, 16));
    const nameBytes = new TextEncoder().encode(name);
    const data = new Uint8Array(ns.length + nameBytes.length);
    data.set(ns);
    data.set(nameBytes, ns.length);
    const h = new Uint8Array(await crypto.subtle.digest("SHA-1", data)).slice(0, 16);
    h[6] = (h[6] & 0x0f) | 0x50;
    h[8] = (h[8] & 0x3f) | 0x80;
    const hex = [...h].map((b) => b.toString(16).padStart(2, "0")).join("");
    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}
// Начало московского дня в секундах: так хранятся отменённые дни в приложении.
function dayKey(moment) {
    const t = moment.getTime();
    const start = Math.floor((t + MSK) / 86400000) * 86400000 - MSK;
    return String(Math.floor(start / 1000));
}
function sameJson(a, b) {
    const sort = (v) => Array.isArray(v) ? v.map(sort)
        : v && typeof v === "object"
            ? Object.fromEntries(Object.entries(v).sort(([x], [y]) => x.localeCompare(y)).map(([k, x]) => [k, sort(x)]))
            : v;
    return JSON.stringify(sort(a)) === JSON.stringify(sort(b));
}
function applyNoShow(payload, rec, begin) {
    if (payload.statuses || payload.partnerStatuses)
        return;
    const key = dayKey(begin);
    const keys = String(payload.cancelledDays ?? "").split(",").filter(Boolean);
    const noShow = rec.attendance === -1 || rec.visit_attendance === -1;
    if (noShow && !keys.includes(key)) {
        payload.cancelledDays = [...keys, key].join(",");
        payload.ycCancelled = true;
    }
    else if (!noShow && payload.ycCancelled && keys.includes(key)) {
        payload.cancelledDays = keys.filter((k) => k !== key).join(",");
        payload.ycCancelled = false;
    }
}
const ycHeaders = () => ({
    Authorization: `Bearer ${env("YCLIENTS_PARTNER_TOKEN")}, User ${env("YCLIENTS_USER_TOKEN")}`,
    Accept: "application/vnd.api.v2+json",
});
async function ycGet(path, params = {}) {
    const url = new URL(`${API_BASE}${path}`);
    for (const [k, v] of Object.entries(params))
        url.searchParams.set(k, v);
    const r = await fetch(url, { headers: ycHeaders() });
    if (!r.ok)
        throw new Error(`YClients ${path}: ${r.status}`);
    return await r.json();
}
async function ycRecords(start, end) {
    const out = [];
    for (let page = 1;; page++) {
        const body = await ycGet(`/records/${env("YCLIENTS_COMPANY_ID")}`, {
            start_date: start, end_date: end, page: String(page), count: String(PAGE),
        });
        if (!body.success)
            throw new Error(`YClients: ${body.meta?.message}`);
        const batch = body.data ?? [];
        out.push(...batch);
        if (batch.length < PAGE)
            return out;
    }
}
async function resourceInstanceId() {
    const body = await ycGet(`/resources/${env("YCLIENTS_COMPANY_ID")}`);
    const found = [];
    for (const res of body.data ?? []) {
        for (const inst of res.instances ?? []) {
            if ((inst.title ?? "").trim() === RESOURCE_TITLE)
                found.push(inst.id);
        }
    }
    if (found.length !== 1)
        throw new Error(`Ресурс «${RESOURCE_TITLE}» найден ${found.length} раз, ожидался один`);
    return found[0];
}
function db() {
    const base = env("SUPABASE_URL").replace(/\/$/, "") + "/rest/v1";
    const key = env("SUPABASE_SERVICE_ROLE_KEY");
    const headers = { apikey: key, Authorization: `Bearer ${key}` };
    return {
        async get(table, query) {
            const rows = [];
            for (let offset = 0;; offset += 1000) {
                const r = await fetch(`${base}/${table}?${query}&limit=1000&offset=${offset}`, { headers });
                if (!r.ok)
                    throw new Error(`Supabase ${table}: ${r.status} ${await r.text()}`);
                const batch = await r.json();
                rows.push(...batch);
                if (batch.length < 1000)
                    return rows;
            }
        },
        async upsert(rows) {
            for (let i = 0; i < rows.length; i += 200) {
                const r = await fetch(`${base}/records?on_conflict=id`, {
                    method: "POST",
                    headers: { ...headers, "Content-Type": "application/json", Prefer: "resolution=merge-duplicates,return=minimal" },
                    body: JSON.stringify(rows.slice(i, i + 200)),
                });
                if (!r.ok)
                    throw new Error(`Supabase upsert: ${r.status} ${await r.text()}`);
            }
        },
    };
}
// --- Олимпик: расписание всех кортов, только для просмотра (YClients не меняем) ---
function mskYmd(d) {
    return new Date(d.getTime() + MSK).toISOString().slice(0, 10);
}
function olimpicStatus(rec) {
    if (rec.attendance === -1 || rec.visit_attendance === -1)
        return "noshow";
    if (rec.attendance === 1 || rec.visit_attendance === 1)
        return "arrived";
    if (rec.attendance === 2 || rec.visit_attendance === 2 || rec.confirmed === 1)
        return "confirmed";
    return "pending";
}
// Групповые события (турниры, группы): отдельный запрос YClients, только чтение.
// Пробуем два адреса: старый «activity» и новый «locations/.../events».
let groupsNote = "";
async function ycGroups(start, end) {
    const id = env("YCLIENTS_COMPANY_ID");
    const paths = [`/activity/${id}/search`, `/locations/${id}/events/search`];
    const errors = [];
    for (const path of paths) {
        try {
            const out = [];
            for (let page = 1; page <= 20; page++) {
                const body = await ycGet(path, { from: start, till: end, page: String(page), count: String(PAGE) });
                const batch = Array.isArray(body.data) ? body.data : [];
                out.push(...batch);
                if (batch.length < PAGE)
                    break;
            }
            groupsNote = `групповых ${out.length}`;
            return out;
        }
        catch (e) {
            errors.push(`${path}: ${e.message}`);
        }
    }
    groupsNote = `групповые не загрузились (${errors.join("; ")})`;
    return [];
}
// Групповое событие приводим к виду записи, чтобы показывать их одинаково.
function groupAsRecord(a) {
    if (a.deleted)
        return null;
    const staffId = a.staff?.id ?? a.staff_id;
    if (!staffId || !a.date)
        return null;
    let date = String(a.date);
    if (!date.includes("T"))
        date = date.replace(" ", "T") + "+03:00";
    return {
        id: 1000000000 + Number(a.id), group: true, datetime: date, seance_length: a.length || 3600,
        staff: { id: staffId, name: a.staff?.name ?? "" },
        client: { name: a.service?.title || "Групповое событие" },
        services: a.service?.title ? [{ title: a.service.title }] : [],
        resource_instances: a.resource_instances ?? [], records_count: a.records_count ?? a.clients_count ?? 0,
        attendance: 0,
    };
}
async function nastyaIdOrNull() {
    try {
        return await resourceInstanceId();
    }
    catch {
        return null;
    }
}
// Разбор записей журнала в корты и брони по дням.
function buildOlimpic(all, nastyaId, groups = []) {
    all = [...all, ...groups.map(groupAsRecord).filter((x) => !!x)];
    const live = all.filter((r) => !r.deleted && r.staff?.id && !/админ/i.test(String(r.staff.name ?? "")));
    // Корты — это сотрудники журнала, у которых есть записи в окне.
    const courtMap = new Map();
    for (const r of live)
        courtMap.set(r.staff.id, String(r.staff.name ?? "").trim() || `Корт ${r.staff.id}`);
    const collator = new Intl.Collator("ru", { numeric: true });
    // Тип корта: по названию корта, а если там не сказано, то по тому, что в записях на нём («Падел…»).
    const isPadelText = (t) => /падел|padel/i.test(t);
    const padelStats = new Map();
    for (const r of live) {
        const st = padelStats.get(r.staff.id) ?? { padel: 0, all: 0 };
        st.all++;
        const text = (r.services ?? []).map((x) => String(x.title ?? "")).join(" ");
        if (isPadelText(text))
            st.padel++;
        padelStats.set(r.staff.id, st);
    }
    const courts = [...courtMap.entries()].map(([id, name]) => {
        const st = padelStats.get(id) ?? { padel: 0, all: 0 };
        const padel = isPadelText(name) || (st.all > 0 && st.padel * 2 > st.all);
        return { id, name, kind: padel ? "padel" : "tennis" };
    }).sort((a, b) => collator.compare(a.name, b.name));
    const perDay = new Map();
    for (const r of live) {
        const begin = new Date(r.datetime);
        const day = mskYmd(begin);
        const services = (r.services ?? []).map((s) => s.title).filter(Boolean).join(", ");
        const client = r.client?.display_name || r.client?.name || services || "Занятие";
        const list = perDay.get(day) ?? [];
        list.push({
            id: r.id, court: r.staff.id, client, start: iso(begin), length: r.seance_length || 3600,
            status: r.group ? "group" : olimpicStatus(r), service: services,
            group: !!r.group, count: r.records_count ?? 0,
            nastya: (r.resource_instances ?? []).some((i) => (nastyaId !== null && i.id === nastyaId) || norm(String(i.title ?? i.name ?? "")) === norm(RESOURCE_TITLE)),
        });
        perDay.set(day, list);
    }
    for (const list of perDay.values())
        list.sort((a, b) => a.start.localeCompare(b.start) || a.id - b.id);
    return { courts, perDay };
}
// Мгновенный запрос из приложения (кнопка «Олимпик»): читаем журнал за выбранный день и отдаём как есть.
// YClients только читаем. День — «гггг-мм-дд» по Москве.
async function olimpicLive(ymd) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(ymd))
        throw new Error("плохая дата");
    const d = new Date(`${ymd}T00:00:00Z`);
    const from = new Date(d.getTime() - 86400000).toISOString().slice(0, 10);
    const to = new Date(d.getTime() + 86400000).toISOString().slice(0, 10);
    const { courts, perDay } = buildOlimpic(await ycRecords(from, to), await nastyaIdOrNull(), await ycGroups(from, to));
    return JSON.stringify({ day: ymd, courts, bookings: perDay.get(ymd) ?? [], debug: groupsNote });
}
async function syncOlimpic(all, supa, coupleId, now, rows, startDay) {
    const { courts, perDay } = buildOlimpic(all, await nastyaIdOrNull(), await ycGroups(mskYmd(startDay), mskYmd(new Date(startDay.getTime() + (DAYS_AHEAD + DAYS_BACK) * 86400000))));
    const existing = new Map();
    for (const r of await supa.get("records", "select=id,payload,deleted_at&kind=eq.planner.olimpic_day"))
        existing.set(r.id, r);
    // Дни окна (с запасом назад) и любые дни, где раньше были записи.
    const days = new Set(perDay.keys());
    for (let t = startDay.getTime(); t <= startDay.getTime() + (DAYS_AHEAD + DAYS_BACK) * 86400000; t += 86400000)
        days.add(mskYmd(new Date(t)));
    const windowStart = mskYmd(startDay);
    let changed = 0;
    for (const day of days) {
        if (day < windowStart)
            continue;
        const id = await uuid5(`olimpic:day:${day}`);
        const bookings = perDay.get(day) ?? [];
        const payload = { day, courts, bookings };
        const old = existing.get(id);
        if (!old && bookings.length === 0)
            continue;
        if (old && !old.deleted_at && sameJson(old.payload, payload))
            continue;
        rows.push({ id, couple_id: coupleId, kind: "planner.olimpic_day", updated_at: now, deleted_at: null, payload });
        changed++;
    }
    return `Олимпик (${groupsNote}): кортов ${courts.length} (${courts.map((c) => c.name).join("; ")}), дней обновлено ${changed}`;
}
async function sync() {
    const excluded = (Deno.env.get("ICLIENTS_EXCLUDE_CLIENTS") ?? "ДЮСШ-13, ДЮСШ-РГК, ДЮСШ-8, ДЮСШ-3")
        .split(",").map((n) => n.trim()).filter(Boolean).map(norm);
    const today = new Date();
    today.setUTCHours(0, 0, 0, 0);
    const startDay = new Date(today.getTime() - DAYS_BACK * 86400000);
    const endDay = new Date(today.getTime() + DAYS_AHEAD * 86400000);
    const ymd = (d) => d.toISOString().slice(0, 10);
    const resourceId = await resourceInstanceId();
    const allRecords = await ycRecords(ymd(startDay), ymd(endDay));
    const fetched = allRecords.filter((r) => !r.deleted && !r.activity_id &&
        (r.resource_instances ?? []).some((i) => i.id === resourceId) &&
        !isExcluded(r.client?.display_name || r.client?.name || "", excluded));
    const supa = db();
    const members = await supa.get("couple_members", `select=couple_id&role=eq.${MEMBER}`);
    if (!members.length)
        throw new Error("В базе нет участника «partner»");
    const coupleId = members[0].couple_id;
    const existing = new Map();
    for (const r of await supa.get("records", "select=id,kind,payload,deleted_at&kind=in.(clients.client,clients.appointment,planner.event)")) {
        existing.set(r.id, r);
    }
    const now = iso(new Date());
    const rows = [];
    // --- клиенты ---
    const byPhone = new Map();
    for (const r of existing.values()) {
        if (r.kind === "clients.client" && !r.deleted_at && r.payload?.member === MEMBER && digits(r.payload.phone ?? "")) {
            byPhone.set(digits(r.payload.phone), r.id);
        }
    }
    const byName = new Map();
    for (const r of existing.values()) {
        if (r.kind === "clients.client" && !r.deleted_at && r.payload?.member === MEMBER && nameKey(r.payload.name ?? "")) {
            byName.set(nameKey(r.payload.name), r.id);
        }
    }
    const clientIds = new Map();
    for (const rec of fetched) {
        const c = rec.client ?? {};
        if (!c.id || clientIds.has(c.id))
            continue;
        const detId = await uuid5(`client:${c.id}`);
        const phone = c.phone ?? "";
        const cname = c.display_name || c.name || "Клиент YClients";
        if (existing.has(detId) && !existing.get(detId).deleted_at)
            clientIds.set(c.id, detId);
        else if (digits(phone) && byPhone.has(digits(phone)))
            clientIds.set(c.id, byPhone.get(digits(phone)));
        else if (byName.has(nameKey(cname)))
            clientIds.set(c.id, byName.get(nameKey(cname)));
        else if (existing.has(detId))
            clientIds.set(c.id, detId); // склеена приложением: не оживляем
        else {
            clientIds.set(c.id, detId);
            byName.set(nameKey(cname), detId);
            rows.push({
                id: detId, couple_id: coupleId, kind: "clients.client", updated_at: now, deleted_at: null,
                payload: { name: cname, phone, note: "", member: MEMBER, createdAt: now, source: "iclients" },
            });
        }
    }
    // --- записи планера ---
    const seen = new Set();
    for (const rec of fetched) {
        const rid = await uuid5(`event:${rec.id}`);
        seen.add(rid);
        const begin = new Date(rec.datetime);
        const finish = new Date(begin.getTime() + (rec.seance_length || 3600) * 1000);
        const client = rec.client ?? {};
        const clientUuid = clientIds.get(client.id);
        const services = (rec.services ?? []).map((s) => s.title).filter(Boolean).join(", ");
        const court = String(rec.staff?.name ?? "").trim() || services;
        const old = existing.get(rid);
        // Запись удалена в планере (корзина): это «надгробие», обратно её не возвращаем никогда.
        if (old?.deleted_at)
            continue;
        let payload;
        let before = {};
        if (!old) {
            payload = {
                title: client.display_name || client.name || "Запись YClients",
                notes: court, start: iso(begin), end: iso(finish), isAllDay: false,
                scope: MEMBER, category: "personal", repeatRule: "none",
                reminderMinutes: 60, createdBy: MEMBER, createdAt: now,
                participantIDs: clientUuid ? [clientUuid.toUpperCase()] : [],
                isPrivate: false, repeatInterval: 1, source: "yclients", v: SCHEMA_VERSION,
            };
        }
        else {
            // Меняем только время и корт: остальное (оплата, статусы, заметки) ведёт Настя.
            payload = { ...(old.payload ?? {}) };
            before = { ...payload };
            payload.start = iso(begin);
            payload.end = iso(finish);
            payload.notes = court;
            payload.v = SCHEMA_VERSION;
        }
        applyNoShow(payload, rec, begin);
        if (old && sameJson(payload, before))
            continue;
        rows.push({ id: rid, couple_id: coupleId, kind: "planner.event", updated_at: now, deleted_at: null, payload });
    }
    // Запись пропала из журнала: отменяем занятие, если Настя не отметила статус.
    const windowStart = iso(startDay);
    for (const [rid, old] of existing) {
        const p = old.payload ?? {};
        if (old.kind === "planner.event" && p.source === "yclients" && !seen.has(rid) && !old.deleted_at &&
            !p.statuses && !p.partnerStatuses && (p.start ?? "") >= windowStart) {
            const key = dayKey(new Date(p.start));
            const keys = String(p.cancelledDays ?? "").split(",").filter(Boolean);
            if (keys.includes(key))
                continue;
            rows.push({ id: rid, couple_id: coupleId, kind: "planner.event", updated_at: now, deleted_at: null,
                payload: { ...p, cancelledDays: [...keys, key].join(",") } });
        }
    }
    // Старые записи первых версий в «Клиентах» убираем.
    for (const [rid, old] of existing) {
        const p = old.payload ?? {};
        if (old.kind === "clients.appointment" && p.source === "iclients" && !old.deleted_at) {
            rows.push({ id: rid, couple_id: coupleId, kind: "clients.appointment", updated_at: now, deleted_at: now, payload: p });
        }
    }
    let olimpic = "";
    try {
        olimpic = await syncOlimpic(allRecords, supa, coupleId, now, rows, startDay);
    }
    catch (e) {
        olimpic = `Олимпик: ошибка ${e.message}`; // не ломаем синхронизацию Насти
    }
    const summary = `Записей в YClients: ${fetched.length}, обновлено в приложении: ${rows.length}. ${olimpic}`;
    // Отметка «синхронизация жива»: приложение этот вид записей не читает.
    rows.push({ id: await uuid5("heartbeat"), couple_id: coupleId, kind: "sys.heartbeat", updated_at: now, deleted_at: null,
        payload: { lastRun: now, summary, engine: "supabase" } });
    await supa.upsert(rows);
    return summary;
}

