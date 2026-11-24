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

// deno-lint-ignore no-explicit-any
type Json = Record<string, any>;

function env(name: string): string {
  const v = (Deno.env.get(name) ?? "").trim();
  if (!v) throw new Error(`Не задан секрет ${name}`);
  return v;
}

function norm(name: string): string {
  let n = name.toLowerCase().replaceAll("ё", "е");
  for (const ch of "-–—_.,") n = n.replaceAll(ch, " ");
  return n.split(/\s+/).filter(Boolean).join(" ");
}

function isExcluded(name: string, excluded: string[]): boolean {
  const n = norm(name);
  return excluded.some((e) => n === e || n.startsWith(e + " "));
}

function iso(d: Date): string {
  return d.toISOString().replace(/\.\d{3}Z$/, "Z");
}

function nameKey(name: string): string {
  return (name ?? "").toLowerCase().replaceAll("ё", "е").split(/\s+/).filter(Boolean).join(" ");
}

function digits(phone: string): string {
  const d = (phone ?? "").replace(/\D/g, "");
  return d.length >= 10 ? d.slice(-10) : d;
}

// uuid5 как в Python (uuid.uuid5), чтобы id записей совпадали со старой синхронизацией.
async function uuid5(name: string): Promise<string> {
  const ns = NS.replaceAll("-", "").match(/../g)!.map((h) => parseInt(h, 16));
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
function dayKey(moment: Date): string {
  const t = moment.getTime();
  const start = Math.floor((t + MSK) / 86400000) * 86400000 - MSK;
  return String(Math.floor(start / 1000));
}

function sameJson(a: unknown, b: unknown): boolean {
  const sort = (v: unknown): unknown =>
    Array.isArray(v) ? v.map(sort)
      : v && typeof v === "object"
        ? Object.fromEntries(Object.entries(v as Json).sort(([x], [y]) => x.localeCompare(y)).map(([k, x]) => [k, sort(x)]))
        : v;
  return JSON.stringify(sort(a)) === JSON.stringify(sort(b));
}

function applyNoShow(payload: Json, rec: Json, begin: Date) {
  if (payload.statuses || payload.partnerStatuses) return;
  const key = dayKey(begin);
  const keys = String(payload.cancelledDays ?? "").split(",").filter(Boolean);
  const noShow = rec.attendance === -1 || rec.visit_attendance === -1;
  if (noShow && !keys.includes(key)) {
    payload.cancelledDays = [...keys, key].join(",");
    payload.ycCancelled = true;
  } else if (!noShow && payload.ycCancelled && keys.includes(key)) {
    payload.cancelledDays = keys.filter((k) => k !== key).join(",");
    payload.ycCancelled = false;
  }
}

const ycHeaders = () => ({
  Authorization: `Bearer ${env("YCLIENTS_PARTNER_TOKEN")}, User ${env("YCLIENTS_USER_TOKEN")}`,
  Accept: "application/vnd.api.v2+json",
});

async function ycGet(path: string, params: Record<string, string> = {}): Promise<Json> {
  const url = new URL(`${API_BASE}${path}`);
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
  const r = await fetch(url, { headers: ycHeaders() });
  if (!r.ok) throw new Error(`YClients ${path}: ${r.status}`);
  return await r.json();
}

async function ycRecords(start: string, end: string): Promise<Json[]> {
  const out: Json[] = [];
  for (let page = 1;; page++) {
    const body = await ycGet(`/records/${env("YCLIENTS_COMPANY_ID")}`, {
      start_date: start, end_date: end, page: String(page), count: String(PAGE),
    });
    if (!body.success) throw new Error(`YClients: ${body.meta?.message}`);
    const batch: Json[] = body.data ?? [];
    out.push(...batch);
    if (batch.length < PAGE) return out;
  }
}

async function resourceInstanceId(): Promise<number> {
  const body = await ycGet(`/resources/${env("YCLIENTS_COMPANY_ID")}`);
  const found: number[] = [];
  for (const res of body.data ?? []) {
    for (const inst of res.instances ?? []) {
      if ((inst.title ?? "").trim() === RESOURCE_TITLE) found.push(inst.id);
    }
  }
  if (found.length !== 1) throw new Error(`Ресурс «${RESOURCE_TITLE}» найден ${found.length} раз, ожидался один`);
  return found[0];
}

function db() {
  const base = env("SUPABASE_URL").replace(/\/$/, "") + "/rest/v1";
  const key = env("SUPABASE_SERVICE_ROLE_KEY");
  const headers = { apikey: key, Authorization: `Bearer ${key}` };
  return {
    async get(table: string, query: string): Promise<Json[]> {
      const rows: Json[] = [];
      for (let offset = 0;; offset += 1000) {
        const r = await fetch(`${base}/${table}?${query}&limit=1000&offset=${offset}`, { headers });
        if (!r.ok) throw new Error(`Supabase ${table}: ${r.status} ${await r.text()}`);
        const batch: Json[] = await r.json();
        rows.push(...batch);
        if (batch.length < 1000) return rows;
      }
    },
    async upsert(rows: Json[]) {
      for (let i = 0; i < rows.length; i += 200) {
        const r = await fetch(`${base}/records?on_conflict=id`, {
          method: "POST",
          headers: { ...headers, "Content-Type": "application/json", Prefer: "resolution=merge-duplicates,return=minimal" },
          body: JSON.stringify(rows.slice(i, i + 200)),
        });
        if (!r.ok) throw new Error(`Supabase upsert: ${r.status} ${await r.text()}`);
      }
    },
  };
}

async function sync(): Promise<string> {
  const excluded = (Deno.env.get("ICLIENTS_EXCLUDE_CLIENTS") ?? "ДЮСШ-13, ДЮСШ-РГК, ДЮСШ-8, ДЮСШ-3")
    .split(",").map((n) => n.trim()).filter(Boolean).map(norm);

  const today = new Date(); today.setUTCHours(0, 0, 0, 0);
  const startDay = new Date(today.getTime() - DAYS_BACK * 86400000);
  const endDay = new Date(today.getTime() + DAYS_AHEAD * 86400000);
  const ymd = (d: Date) => d.toISOString().slice(0, 10);

  const resourceId = await resourceInstanceId();
  const fetched = (await ycRecords(ymd(startDay), ymd(endDay))).filter((r) =>
    !r.deleted && !r.activity_id &&
    (r.resource_instances ?? []).some((i: Json) => i.id === resourceId) &&
    !isExcluded(r.client?.display_name || r.client?.name || "", excluded)
  );

  const supa = db();
  const members = await supa.get("couple_members", `select=couple_id&role=eq.${MEMBER}`);
  if (!members.length) throw new Error("В базе нет участника «partner»");
  const coupleId = members[0].couple_id;

  const existing = new Map<string, Json>();
  for (const r of await supa.get("records", "select=id,kind,payload,deleted_at&kind=in.(clients.client,clients.appointment,planner.event)")) {
    existing.set(r.id, r);
  }
  const now = iso(new Date());
  const rows: Json[] = [];

  // --- клиенты ---
  const byPhone = new Map<string, string>();
  for (const r of existing.values()) {
    if (r.kind === "clients.client" && !r.deleted_at && r.payload?.member === MEMBER && digits(r.payload.phone ?? "")) {
      byPhone.set(digits(r.payload.phone), r.id);
    }
  }
  const byName = new Map<string, string>();
  for (const r of existing.values()) {
    if (r.kind === "clients.client" && !r.deleted_at && r.payload?.member === MEMBER && nameKey(r.payload.name ?? "")) {
      byName.set(nameKey(r.payload.name), r.id);
    }
  }
  const clientIds = new Map<number, string>();
  for (const rec of fetched) {
    const c = rec.client ?? {};
    if (!c.id || clientIds.has(c.id)) continue;
    const detId = await uuid5(`client:${c.id}`);
    const phone: string = c.phone ?? "";
    const cname: string = c.display_name || c.name || "Клиент YClients";
    if (existing.has(detId) && !existing.get(detId)!.deleted_at) clientIds.set(c.id, detId);
    else if (digits(phone) && byPhone.has(digits(phone))) clientIds.set(c.id, byPhone.get(digits(phone))!);
    else if (byName.has(nameKey(cname))) clientIds.set(c.id, byName.get(nameKey(cname))!);
    else if (existing.has(detId)) clientIds.set(c.id, detId); // склеена приложением: не оживляем
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
  const seen = new Set<string>();
  for (const rec of fetched) {
    const rid = await uuid5(`event:${rec.id}`);
    seen.add(rid);
    const begin = new Date(rec.datetime);
    const finish = new Date(begin.getTime() + (rec.seance_length || 3600) * 1000);
    const client = rec.client ?? {};
    const clientUuid = clientIds.get(client.id);
    const services = (rec.services ?? []).map((s: Json) => s.title).filter(Boolean).join(", ");
    const court = String(rec.staff?.name ?? "").trim() || services;
    const old = existing.get(rid);
    // Запись удалена в планере (корзина): это «надгробие», обратно её не возвращаем никогда.
    if (old?.deleted_at) continue;
    let payload: Json;
    let before: Json = {};
    if (!old) {
      payload = {
        title: client.display_name || client.name || "Запись YClients",
        notes: court, start: iso(begin), end: iso(finish), isAllDay: false,
        scope: MEMBER, category: "personal", repeatRule: "none",
        reminderMinutes: 60, createdBy: MEMBER, createdAt: now,
        participantIDs: clientUuid ? [clientUuid.toUpperCase()] : [],
        isPrivate: false, repeatInterval: 1, source: "yclients", v: SCHEMA_VERSION,
      };
    } else {
      // Меняем только время и корт: остальное (оплата, статусы, заметки) ведёт Настя.
      payload = { ...(old.payload ?? {}) };
      before = { ...payload };
      payload.start = iso(begin);
      payload.end = iso(finish);
      payload.notes = court;
      payload.v = SCHEMA_VERSION;
    }
    applyNoShow(payload, rec, begin);
    if (old && sameJson(payload, before)) continue;
    rows.push({ id: rid, couple_id: coupleId, kind: "planner.event", updated_at: now, deleted_at: null, payload });
  }

  // Запись пропала из журнала: отменяем занятие, если Настя не отметила статус.
  const windowStart = iso(startDay);
  for (const [rid, old] of existing) {
    const p: Json = old.payload ?? {};
    if (old.kind === "planner.event" && p.source === "yclients" && !seen.has(rid) && !old.deleted_at &&
        !p.statuses && !p.partnerStatuses && (p.start ?? "") >= windowStart) {
      const key = dayKey(new Date(p.start));
      const keys = String(p.cancelledDays ?? "").split(",").filter(Boolean);
      if (keys.includes(key)) continue;
      rows.push({ id: rid, couple_id: coupleId, kind: "planner.event", updated_at: now, deleted_at: null,
        payload: { ...p, cancelledDays: [...keys, key].join(",") } });
    }
  }

  // Старые записи первых версий в «Клиентах» убираем.
  for (const [rid, old] of existing) {
    const p: Json = old.payload ?? {};
    if (old.kind === "clients.appointment" && p.source === "iclients" && !old.deleted_at) {
      rows.push({ id: rid, couple_id: coupleId, kind: "clients.appointment", updated_at: now, deleted_at: now, payload: p });
    }
  }

  if (rows.length) await supa.upsert(rows);
  return `Записей в YClients: ${fetched.length}, обновлено в приложении: ${rows.length}`;
}
