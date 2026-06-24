/* eslint-disable @typescript-eslint/no-explicit-any */
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import pg from "npm:pg@8.11.5";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const DB_URL = Deno.env.get("SUPABASE_DB_URL") ?? "";

const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

const { Pool } = pg;
const pool = new Pool({ connectionString: DB_URL, max: 2 });

function jsonResponse(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function pad(num: number, width: number) {
  const s = String(num);
  return s.length >= width ? s : "0".repeat(width - s.length) + s;
}

function loc3(raw: string | null | undefined): string {
  const v = (raw ?? "").toString().trim();
  if (!v) return "UNK";
  // Normalize:
  // - uppercase
  // - remove special characters
  // - ignore spaces/hyphens when taking first 3 characters
  const cleaned = v.toUpperCase().replace(/[^A-Z]/g, "");
  if (!cleaned) return "UNK";
  const first = cleaned.slice(0, 3);
  return first.length >= 3 ? first : (first + "XXX").slice(0, 3);
}

async function getProviderLocation(userId: string): Promise<{ state: string | null; lga: string | null; ward: string | null }> {
  // Source of truth: business address table when present; fallback to users profile.
  const { data: addr, error: addrErr } = await adminClient
    .from("user_business_addresses")
    .select("state, lga, ward")
    .eq("user_id", userId)
    .maybeSingle();
  if (addrErr) {
    // Non-fatal: fall back to users.
  }
  if (addr) {
    return {
      state: (addr as any).state ?? null,
      lga: (addr as any).lga ?? null,
      ward: (addr as any).ward ?? null,
    };
  }

  const { data: u, error: uErr } = await adminClient.from("users").select("state, lga, ward").eq("id", userId).maybeSingle();
  if (uErr) throw uErr;
  return { state: (u as any)?.state ?? null, lga: (u as any)?.lga ?? null, ward: (u as any)?.ward ?? null };
}

function stateToCode3(stateRaw: string | null): string | null {
  if (!stateRaw) return null;
  const s = stateRaw === "FCT" ? "Abuja FCT" : stateRaw;
  const map: Record<string, string> = {
    "Abia": "ABI",
    "Adamawa": "ADA",
    "Akwa Ibom": "AKI",
    "Anambra": "ANB",
    "Bauchi": "BAU",
    "Bayelsa": "BAY",
    "Benue": "BEN",
    "Borno": "BOR",
    "Cross River": "CRS",
    "Delta": "DEL",
    "Ebonyi": "EBO",
    "Edo": "EDO",
    "Ekiti": "EKI",
    "Enugu": "ENU",
    "Abuja FCT": "ABU",
    "Gombe": "GMB",
    "Imo": "IMO",
    "Jigawa": "JIG",
    "Kaduna": "KAD",
    "Kano": "KAN",
    "Katsina": "KAT",
    "Kebbi": "KEB",
    "Kogi": "KOG",
    "Kwara": "KWA",
    "Lagos": "LAG",
    "Nasarawa": "NAS",
    "Niger": "NIG",
    "Ogun": "OGU",
    "Ondo": "OND",
    "Osun": "OSU",
    "Oyo": "OYO",
    "Plateau": "PLA",
    "Rivers": "RIV",
    "Sokoto": "SOK",
    "Taraba": "TAR",
    "Yobe": "YOB",
    "Zamfara": "ZAM",
  };
  return map[s] ?? null;
}

async function ensureSchema() {
  const client = await pool.connect();
  try {
    await client.query("begin");

    // Needed for gen_random_uuid()
    await client.query("create extension if not exists pgcrypto;");

    await client.query(`create table if not exists public.counters (
      key text primary key,
      value bigint not null default 0,
      updated_at timestamptz not null default now()
    );`);

    // Users: field provider unique id (match existing lowercase naming style)
    await client.query(`alter table public.users add column if not exists fieldprovideruniqueid text null;`);
    await client.query(`create unique index if not exists users_fieldprovideruniqueid_uniq on public.users (fieldprovideruniqueid) where fieldprovideruniqueid is not null;`);

    // Clients table
    await client.query(`create table if not exists public.clients (
      id uuid primary key default gen_random_uuid(),
      provideruserid uuid not null,
      fieldproviderid text not null,
      clientid text not null,
      name text not null,
      dateofbirth date null,
      sex text not null,
      phonenumber text not null,
      createdat timestamptz not null default now(),
      updatedat timestamptz not null default now()
    );`);
    await client.query(`create unique index if not exists clients_clientid_uniq on public.clients (clientid);`);
    await client.query(`create index if not exists clients_provideruserid_idx on public.clients (provideruserid);`);

    // Test records additions
    await client.query(`alter table public.test_records add column if not exists age integer null;`);
    await client.query(`alter table public.test_records add column if not exists phonenumber text null;`);
    await client.query(`alter table public.test_records add column if not exists dateofbirth date null;`);

    // Stock movements additions
    await client.query(`alter table public.stock_movements add column if not exists batchnumber text null;`);
    await client.query(`alter table public.stock_movements add column if not exists expirydate date null;`);

    await client.query("commit");
  } catch (e) {
    await client.query("rollback");
    throw e;
  } finally {
    client.release();
  }
}

async function getAuthUser(req: Request) {
  const authHeader = req.headers.get("authorization") ?? "";
  const jwt = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : null;
  if (!jwt) return null;
  const { data, error } = await adminClient.auth.getUser(jwt);
  if (error) return null;
  return data.user;
}

async function getProfile(userId: string) {
  const { data, error } = await adminClient.from("users").select("id, role, state, lga, ward, fieldprovideruniqueid").eq("id", userId).maybeSingle();
  if (error) throw error;
  return data as any;
}

async function nextCounter(key: string): Promise<number> {
  const client = await pool.connect();
  try {
    const res = await client.query(
      `insert into public.counters(key, value) values ($1, 1)
       on conflict (key) do update set value = public.counters.value + 1, updated_at = now()
       returning value;`,
      [key],
    );
    return Number(res.rows[0].value);
  } finally {
    client.release();
  }
}

async function ensureFieldProviderId(userId: string) {
  const profile = await getProfile(userId);
  if (!profile) throw new Error("Profile not found");
  if (profile.role !== "fieldProvider") throw new Error("Only fieldProvider can request this action");
  if (profile.fieldprovideruniqueid) return { fieldProviderUniqueId: profile.fieldprovideruniqueid };

  const code = stateToCode3(profile.state);
  if (!code) throw new Error("FieldProvider must have a valid state before generating ID");

  // Retry loop in case of extremely rare collisions.
  for (let attempt = 0; attempt < 5; attempt++) {
    const seq = await nextCounter(`fp:${code}`);
    const newId = `${code}-${pad(seq, 4)}`;
    const { error } = await adminClient.from("users").update({ fieldprovideruniqueid: newId }).eq("id", userId).is("fieldprovideruniqueid", null);
    if (!error) return { fieldProviderUniqueId: newId };
  }
  throw new Error("Failed to allocate unique FieldProvider ID");
}

async function upsertClientForProvider(userId: string, body: any) {
  const profile = await getProfile(userId);
  if (!profile) throw new Error("Profile not found");
  if (profile.role !== "fieldProvider") throw new Error("Only fieldProvider can create clients");

  const ensured = await ensureFieldProviderId(userId);
  const fpId = ensured.fieldProviderUniqueId;

  const desiredClientId = (body.desiredClientId ?? "").toString().trim();
  const name = (body.name ?? "").toString().trim();
  const sex = (body.sex ?? "").toString().trim();
  const phoneNumber = (body.phoneNumber ?? "").toString().trim();
  const dateOfBirth = (body.dateOfBirth ?? null) ? new Date(body.dateOfBirth) : null;

  if (!name) throw new Error("Client name is required");
  if (!sex) throw new Error("Client sex is required");
  if (!phoneNumber) throw new Error("Client phone number is required");

  const normalizeTypeSegment = (raw: any): string => {
    const v = (raw ?? "").toString().trim();
    if (!v) return "";
    const cleaned = v.toUpperCase().replace(/[^A-Z]/g, "");
    if (!cleaned) return "";
    const first = cleaned.length >= 3 ? cleaned.substring(0, 3) : cleaned.padEnd(3, "X");
    return first;
  };

  // Strict: ward/type segment must be real. If the client didn't send it, we
  // derive from the provider's Business profile (source of truth) and enforce
  // it is present.
  let typeSegment = normalizeTypeSegment(body.typeSegment ?? body.ward ?? body.wardSegment ?? "");
  if (!typeSegment) {
    const loc = await getProviderLocation(userId);
    typeSegment = loc3(loc.ward);
  }
  if (!typeSegment || typeSegment === "UNK") throw new Error("Cannot allocate client code: provider ward is missing");

  // Prefer backend-generated sequential codes: STATE-LGA-TYPE-0000001
  // Desired codes are only honored when they already match the strict format.
  const desiredOk = desiredClientId && /^[A-Z]{3}-[A-Z]{3}-[A-Z]{3}-\d{7}$/.test(desiredClientId.toUpperCase());

  let clientId = desiredOk ? desiredClientId.toUpperCase() : "";

  // If a desired code collides with a different provider, do NOT upsert into that row.
  if (clientId) {
    const { data: existing, error: exErr } = await adminClient
      .from("clients")
      .select("clientid, provideruserid")
      .eq("clientid", clientId)
      .maybeSingle();
    if (exErr) throw exErr;
    if (existing && (existing as any).provideruserid && (existing as any).provideruserid !== userId) {
      clientId = "";
    }
  }

  if (!clientId) {
    const { data: code, error: codeErr } = await adminClient.rpc("allocate_client_code", {
      provider_user_id: userId,
      type_segment: typeSegment,
    });
    if (codeErr) throw codeErr;
    clientId = (code as any)?.toString?.() ?? String(code ?? "");
    clientId = clientId.trim().toUpperCase();
    if (!clientId) throw new Error("Failed to allocate client code");

    const { data, error } = await adminClient
      .from("clients")
      .insert({
        provideruserid: userId,
        fieldproviderid: fpId,
        clientid: clientId,
        name,
        sex,
        phonenumber: phoneNumber,
        dateofbirth: dateOfBirth && !isNaN(dateOfBirth.getTime()) ? dateOfBirth.toISOString().slice(0, 10) : null,
        updatedat: new Date().toISOString(),
      })
      .select()
      .maybeSingle();
    if (error) throw error;
    if (!data) throw new Error("Failed to create client");

    return {
      id: (data as any).id,
      providerUserId: (data as any).provideruserid,
      fieldProviderId: (data as any).fieldproviderid,
      clientId: (data as any).clientid,
      name: (data as any).name,
      dateOfBirth: (data as any).dateofbirth,
      sex: (data as any).sex,
      phoneNumber: (data as any).phonenumber,
      createdAt: (data as any).createdat,
      updatedAt: (data as any).updatedat,
    };
  }

  const payload: any = {
    provideruserid: userId,
    fieldproviderid: fpId,
    clientid: clientId,
    name,
    sex,
    phonenumber: phoneNumber,
    updatedat: new Date().toISOString(),
  };
  if (dateOfBirth && !isNaN(dateOfBirth.getTime())) payload.dateofbirth = dateOfBirth.toISOString().slice(0, 10);

  // Upsert by client_id (unique). Safe because we already verified the code isn't owned by a different provider.
  const { data, error } = await adminClient.from("clients").upsert(payload, { onConflict: "clientid" }).select().single();
  if (error) throw error;

  return {
    id: data.id,
    providerUserId: data.provideruserid,
    fieldProviderId: data.fieldproviderid,
    clientId: data.clientid,
    name: data.name,
    dateOfBirth: data.dateofbirth,
    sex: data.sex,
    phoneNumber: data.phonenumber,
    createdAt: data.createdat,
    updatedAt: data.updatedat,
  };
}

async function requireAdmin(userId: string) {
  const profile = await getProfile(userId);
  const role = profile?.role;
  if (role !== "admin" && role !== "superAdmin") throw new Error("Admin privileges required");
}

async function backfillAll(userId: string) {
  await requireAdmin(userId);

  // Backfill fieldProvider IDs (only if state is present)
  const { data: fps, error: fpErr } = await adminClient
    .from("users")
    .select("id, state, role, fieldprovideruniqueid")
    .eq("role", "fieldProvider")
    .is("fieldprovideruniqueid", null);
  if (fpErr) throw fpErr;

  for (const u of fps ?? []) {
    try {
      await ensureFieldProviderId(u.id);
    } catch (_e) {
      // Skip invalid state rows safely.
    }
  }

  // Backfill clients from existing test_records, creating stable client rows.
  // We only create a client row when:
  // - record has a non-empty client_id
  // - and the client_id is not already in clients
  const { data: tests, error: tErr } = await adminClient
    .from("test_records")
    // Use only known existing column names (this project uses lowercase column style).
    .select("userid, clientid, clientname, sex, phonenumber, dateofbirth")
    .limit(5000);
  if (tErr) throw tErr;

  const existingIds = new Set<string>();
  const { data: existing, error: eErr } = await adminClient.from("clients").select("clientid").limit(10000);
  if (eErr) throw eErr;
  for (const c of existing ?? []) existingIds.add((c.clientid ?? "").toString());

  for (const r of tests ?? []) {
    const providerUserId = (r.userid ?? "").toString();
    const clientId = (r.clientid ?? "").toString().trim();
    if (!providerUserId || !clientId) continue;
    if (existingIds.has(clientId)) continue;

    const profile = await getProfile(providerUserId);
    if (!profile || profile.role !== "fieldProvider") continue;
    const fpId = profile.fieldprovideruniqueid;
    if (!fpId) continue;

    const name = (r.clientname ?? "").toString().trim();
    const sex = (r.sex ?? "").toString().trim();
    const phone = (r.phonenumber ?? "").toString().trim();
    const dob = (r.dateofbirth ?? null) ? new Date(r.dateofbirth) : null;
    if (!name || !sex || !phone) continue;

    await adminClient.from("clients").upsert({
      provideruserid: providerUserId,
      fieldproviderid: fpId,
      clientid: clientId,
      name,
      sex,
      phonenumber: phone,
      dateofbirth: dob && !isNaN(dob.getTime()) ? dob.toISOString().slice(0, 10) : null,
      updatedat: new Date().toISOString(),
    }, { onConflict: "clientid" });

    existingIds.add(clientId);
  }

  return { ok: true, fieldProvidersBackfilled: (fps ?? []).length };
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    await ensureSchema();

    const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
    const action = (body.action ?? "").toString();

    if (action === "ping") return jsonResponse({ ok: true });

    const authUser = await getAuthUser(req);
    if (!authUser) return jsonResponse({ ok: false, error: "Unauthorized" }, 401);

    if (action === "ensure_fieldprovider_id") {
      const result = await ensureFieldProviderId(authUser.id);
      return jsonResponse({ ok: true, ...result });
    }

    if (action === "upsert_client") {
      const client = await upsertClientForProvider(authUser.id, body);
      return jsonResponse(client);
    }

    if (action === "backfill_all") {
      const res = await backfillAll(authUser.id);
      return jsonResponse(res);
    }

    return jsonResponse({ ok: false, error: "Unknown action" }, 400);
  } catch (e) {
    return jsonResponse({ ok: false, error: (e as Error).message ?? String(e) }, 500);
  }
});
