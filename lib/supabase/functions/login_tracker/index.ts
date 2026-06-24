import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-max-age": "86400",
};

type Json = Record<string, unknown>;

function jsonResponse(status: number, body: Json) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "content-type": "application/json" },
  });
}

function getBearerToken(req: Request) {
  const h = req.headers.get("authorization") || req.headers.get("Authorization") || "";
  const m = h.match(/^Bearer\s+(.+)$/i);
  return m ? m[1].trim() : "";
}

async function requireAuthedUserId(url: string, anonKey: string, req: Request) {
  const token = getBearerToken(req);
  if (!token) throw new Error("Not authenticated");
  const authed = createClient(url, anonKey, { global: { headers: { Authorization: `Bearer ${token}` } } });
  const { data, error } = await authed.auth.getUser();
  if (error || !data?.user?.id) throw new Error("Not authenticated");
  return { userId: data.user.id, token };
}

async function requireSuperAdminFull(adminClient: any, requesterId: string) {
  const { data, error } = await adminClient.from("users").select("*").eq("id", requesterId).maybeSingle();
  if (error) throw error;
  const role = (data as any)?.role?.toString?.() ?? "";
  const adminScope = ((data as any)?.admin_scope ?? (data as any)?.adminScope ?? "").toString();
  const email = ((data as any)?.email ?? "").toString().trim().toLowerCase();
  const ok = role === "superAdmin" || adminScope === "full" || email === "tundeoyelana@gmail.com";
  if (!ok) throw new Error("Forbidden");
  return data as any;
}

function iso(d: Date) {
  return d.toISOString();
}

function safeInt(v: unknown) {
  const n = typeof v === "number" ? v : parseInt(String(v ?? ""), 10);
  return Number.isFinite(n) ? n : 0;
}

function safeBool(v: unknown) {
  if (v === true) return true;
  const s = String(v ?? "").trim().toLowerCase();
  return s == "true" || s == "1" || s == "yes";
}

function csvEscape(v: unknown) {
  const s = String(v ?? "");
  if (s.includes("\"") || s.includes(",") || s.includes("\n") || s.includes("\r")) return `"${s.replaceAll('"', '""')}"`;
  return s;
}

function fmtDateLocal(isoStr: string) {
  // Keep consistent regardless of client locale: YYYY-MM-DD from ISO.
  // (ISO 8601 starts with date portion.)
  return (isoStr || "").slice(0, 10);
}

function fmtTimeLocal(isoStr: string) {
  // HH:MM:SS from ISO (best-effort).
  const m = (isoStr || "").match(/T(\d\d:\d\d:\d\d)/);
  return m ? m[1] : "";
}

function derivedSessionStatus(s: any, now: Date) {
  const raw = String(s?.status ?? "").trim().toLowerCase();
  if (raw === "signed_out") return "signed_out";
  if (raw === "active") {
    const lastSeen = s?.last_seen_at ? new Date(s.last_seen_at) : null;
    // Mark as expired if we haven't seen a heartbeat in 30 minutes.
    if (lastSeen && now.getTime() - lastSeen.getTime() > 30 * 60 * 1000) return "expired";
    return "active";
  }
  return raw || "unknown";
}

function compactIds(ids: string[], maxIds: number) {
  if (!Array.isArray(ids) || ids.length === 0) return "";
  const shown = ids.slice(0, Math.max(0, maxIds));
  const more = ids.length - shown.length;
  return more > 0 ? `${shown.join("|")} (+${more} more)` : shown.join("|");
}

async function fetchTestRecordsInWindow(adminClient: any, userId: string, startIso: string, endIso: string) {
  const variants: Array<{ userCol: string; dateCol: string; select: string }> = [
    { userCol: "userid", dateCol: "testdate", select: "id,program" },
    { userCol: "user_id", dateCol: "test_date", select: "id,program" },
    { userCol: "userId", dateCol: "testDate", select: "id,program" },
  ];

  let lastErr: any = null;
  for (const v of variants) {
    try {
      const { data, error } = await adminClient
        .from("test_records")
        .select(v.select)
        .eq(v.userCol, userId)
        .gte(v.dateCol, startIso)
        .lte(v.dateCol, endIso);
      if (error) throw error;
      return Array.isArray(data) ? data : [];
    } catch (e) {
      lastErr = e;
      const msg = String((e as any)?.message ?? e);
      const schemaErr = msg.includes("does not exist") || msg.includes("schema cache") || msg.includes("Could not find the");
      if (!schemaErr) break;
    }
  }

  // If we can't read test_records in a schema-safe way, do not fail the whole list.
  console.error("fetchTestRecordsInWindow failed:", lastErr);
  return [];
}

async function fetchPreventionRecordsInWindow(adminClient: any, userId: string, startIso: string, endIso: string) {
  const variants: Array<{ userCol: string; dateCol: string }> = [
    { userCol: "userid", dateCol: "createdat" },
    { userCol: "user_id", dateCol: "created_at" },
    { userCol: "userId", dateCol: "createdAt" },
  ];

  let lastErr: any = null;
  for (const v of variants) {
    try {
      const { data, error } = await adminClient
        .from("prevention_messaging_records")
        .select("id")
        .eq(v.userCol, userId)
        .gte(v.dateCol, startIso)
        .lte(v.dateCol, endIso);
      if (error) throw error;
      return Array.isArray(data) ? data : [];
    } catch (e) {
      lastErr = e;
      const msg = String((e as any)?.message ?? e);
      const schemaErr = msg.includes("does not exist") || msg.includes("schema cache") || msg.includes("Could not find the");
      if (!schemaErr) break;
    }
  }

  console.error("fetchPreventionRecordsInWindow failed:", lastErr);
  return [];
}

async function fetchSessionsInRange(adminClient: any, startIso: string, endIso: string, limit: number, offset: number) {
  let q = adminClient
    .from("user_login_sessions")
    .select("id,user_id,signed_in_at,signed_out_at,last_seen_at,status,end_reason,app_platform,app_version,device_id")
    .order("signed_in_at", { ascending: false });
  if (startIso) q = q.gte("signed_in_at", startIso);
  if (endIso) q = q.lte("signed_in_at", endIso);
  if (limit > 0) q = q.range(offset, offset + limit - 1);
  const { data, error } = await q;
  if (error) throw error;
  return Array.isArray(data) ? data : [];
}

async function countSessions(adminClient: any, startIso: string, endIso: string) {
  let q = adminClient.from("user_login_sessions").select("id", { count: "exact", head: true });
  if (startIso) q = q.gte("signed_in_at", startIso);
  if (endIso) q = q.lte("signed_in_at", endIso);
  const { count, error } = await q;
  if (error) throw error;
  return count ?? 0;
}

async function countUniqueUsers(adminClient: any, startIso: string, endIso: string) {
  // Supabase doesn't directly expose count(distinct ...) via PostgREST count.
  // We do a small server-side de-dupe by selecting user_id within range.
  // For a single day this is cheap, and stays backend-only.
  let q = adminClient.from("user_login_sessions").select("user_id");
  if (startIso) q = q.gte("signed_in_at", startIso);
  if (endIso) q = q.lte("signed_in_at", endIso);
  const { data, error } = await q;
  if (error) throw error;
  const ids = new Set<string>();
  for (const r of data ?? []) {
    const id = String((r as any)?.user_id ?? "").trim();
    if (id) ids.add(id);
  }
  return ids.size;
}

async function fetchProfilesByIds(adminClient: any, userIds: string[]) {
  if (userIds.length === 0) return new Map<string, any>();
  const { data, error } = await adminClient.from("users").select("*").in("id", userIds);
  if (error) throw error;
  const map = new Map<string, any>();
  for (const p of data ?? []) map.set(String((p as any).id), p);
  return map;
}

type ActivityCounts = {
  malariaCount: number;
  hivCount: number;
  preventionMessagingCount: number;
  totalCount: number;
  malariaIds: string[];
  hivIds: string[];
  preventionMessagingIds: string[];
};

function emptyActivity(): ActivityCounts {
  return { malariaCount: 0, hivCount: 0, preventionMessagingCount: 0, totalCount: 0, malariaIds: [], hivIds: [], preventionMessagingIds: [] };
}

function normalizeProgram(raw: unknown) {
  const p = String(raw ?? "").trim().toLowerCase();
  if (p === "malaria") return "malaria";
  if (p === "hiv") return "hiv";
  if (p === "tb") return "tb";
  // Some older records might label HIV as hiv_tb or similar.
  if (p.includes("hiv")) return "hiv";
  return p || "unknown";
}

function chooseTimeField(obj: any, candidates: string[]) {
  for (const c of candidates) {
    const v = obj?.[c];
    if (v) return String(v);
  }
  return "";
}

function chooseUserField(obj: any, candidates: string[]) {
  for (const c of candidates) {
    const v = obj?.[c];
    if (v) return String(v);
  }
  return "";
}

async function fetchAllTestRecordsForUsers(adminClient: any, userIds: string[], startIso: string, endIso: string) {
  // Schema-flex: try a handful of known column shapes.
  const variants: Array<{ userCol: string; dateCol: string; select: string }> = [
    { userCol: "userid", dateCol: "testdate", select: "id,program,userid,testdate" },
    { userCol: "user_id", dateCol: "test_date", select: "id,program,user_id,test_date" },
    { userCol: "userId", dateCol: "testDate", select: "id,program,userId,testDate" },
  ];
  let lastErr: any = null;
  for (const v of variants) {
    try {
      // Page through if needed.
      const out: any[] = [];
      const pageSize = 1000;
      for (let offset = 0; offset < 200000; offset += pageSize) {
        const { data, error } = await adminClient
          .from("test_records")
          .select(v.select)
          .in(v.userCol, userIds)
          .gte(v.dateCol, startIso)
          .lte(v.dateCol, endIso)
          .range(offset, offset + pageSize - 1);
        if (error) throw error;
        const rows = Array.isArray(data) ? data : [];
        out.push(...rows);
        if (rows.length < pageSize) break;
      }
      return out;
    } catch (e) {
      lastErr = e;
      const msg = String((e as any)?.message ?? e);
      const schemaErr = msg.includes("does not exist") || msg.includes("schema cache") || msg.includes("Could not find the");
      if (!schemaErr) break;
    }
  }
  console.error("fetchAllTestRecordsForUsers failed:", lastErr);
  return [];
}

async function fetchAllPreventionRecordsForUsers(adminClient: any, userIds: string[], startIso: string, endIso: string) {
  const variants: Array<{ userCol: string; dateCol: string; select: string }> = [
    { userCol: "userid", dateCol: "createdat", select: "id,userid,createdat" },
    { userCol: "user_id", dateCol: "created_at", select: "id,user_id,created_at" },
    { userCol: "userId", dateCol: "createdAt", select: "id,userId,createdAt" },
  ];
  let lastErr: any = null;
  for (const v of variants) {
    try {
      const out: any[] = [];
      const pageSize = 1000;
      for (let offset = 0; offset < 200000; offset += pageSize) {
        const { data, error } = await adminClient
          .from("prevention_messaging_records")
          .select(v.select)
          .in(v.userCol, userIds)
          .gte(v.dateCol, startIso)
          .lte(v.dateCol, endIso)
          .range(offset, offset + pageSize - 1);
        if (error) throw error;
        const rows = Array.isArray(data) ? data : [];
        out.push(...rows);
        if (rows.length < pageSize) break;
      }
      return out;
    } catch (e) {
      lastErr = e;
      const msg = String((e as any)?.message ?? e);
      const schemaErr = msg.includes("does not exist") || msg.includes("schema cache") || msg.includes("Could not find the");
      if (!schemaErr) break;
    }
  }
  console.error("fetchAllPreventionRecordsForUsers failed:", lastErr);
  return [];
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const body = (await req.json().catch(() => ({}))) as any;
    const action = (body.action ?? "").toString();

    const adminClient = createClient(url, serviceRoleKey);

    if (action === "start_session") {
      const { userId } = await requireAuthedUserId(url, anonKey, req);

      const appPlatform = (body.appPlatform ?? "").toString().trim() || null;
      const appVersion = (body.appVersion ?? "").toString().trim() || null;
      const deviceId = (body.deviceId ?? "").toString().trim() || null;

      const now = new Date();
      const { data, error } = await adminClient
        .from("user_login_sessions")
        .insert({
          user_id: userId,
          signed_in_at: iso(now),
          last_seen_at: iso(now),
          status: "active",
          app_platform: appPlatform,
          app_version: appVersion,
          device_id: deviceId,
          updated_at: iso(now),
        })
        .select("id, user_id, signed_in_at, last_seen_at, status")
        .single();
      if (error) throw error;
      return jsonResponse(200, { ok: true, session: data });
    }

    if (action === "heartbeat") {
      const { userId } = await requireAuthedUserId(url, anonKey, req);
      const sessionId = (body.sessionId ?? "").toString().trim();
      const now = new Date();

      if (sessionId) {
        const { data, error } = await adminClient
          .from("user_login_sessions")
          .update({ last_seen_at: iso(now), updated_at: iso(now) })
          .eq("id", sessionId)
          .eq("user_id", userId)
          .is("signed_out_at", null)
          .select("id")
          .maybeSingle();
        if (error) throw error;
        return jsonResponse(200, { ok: true, updated: !!data });
      }

      const { data, error } = await adminClient
        .from("user_login_sessions")
        .update({ last_seen_at: iso(now), updated_at: iso(now) })
        .eq("user_id", userId)
        .is("signed_out_at", null)
        .order("signed_in_at", { ascending: false })
        .limit(1)
        .select("id")
        .maybeSingle();
      if (error) throw error;
      return jsonResponse(200, { ok: true, updated: !!data, sessionId: (data as any)?.id ?? null });
    }

    if (action === "end_session") {
      const { userId } = await requireAuthedUserId(url, anonKey, req);
      const sessionId = (body.sessionId ?? "").toString().trim();
      if (!sessionId) return jsonResponse(400, { ok: false, error: "sessionId is required" });

      const now = new Date();
      const { data: existing, error: exErr } = await adminClient
        .from("user_login_sessions")
        .select("id, signed_in_at")
        .eq("id", sessionId)
        .eq("user_id", userId)
        .maybeSingle();
      if (exErr) throw exErr;
      if (!existing) return jsonResponse(200, { ok: true, updated: false });

      const startedAt = new Date((existing as any).signed_in_at);
      const durationSeconds = Math.max(0, Math.floor((now.getTime() - startedAt.getTime()) / 1000));

      const { data, error } = await adminClient
        .from("user_login_sessions")
        .update({
          signed_out_at: iso(now),
          last_seen_at: iso(now),
          status: "signed_out",
          end_reason: "signed_out",
          updated_at: iso(now),
        })
        .eq("id", sessionId)
        .eq("user_id", userId)
        .select("id")
        .maybeSingle();
      if (error) throw error;
      return jsonResponse(200, { ok: true, updated: !!data, durationSeconds });
    }

    if (action === "list_sessions") {
      const { userId: requesterId } = await requireAuthedUserId(url, anonKey, req);
      await requireSuperAdminFull(adminClient, requesterId);

      const limit = Math.min(200, Math.max(1, safeInt(body.limit) || 100));
      const startIso = (body.start ?? "").toString().trim();
      const endIso = (body.end ?? "").toString().trim();
      const filterUser = (body.userId ?? "").toString().trim();
      const filterRole = (body.role ?? "").toString().trim();

      const includeActivity = safeBool(body.includeActivity);

      let q = adminClient
        .from("user_login_sessions")
        .select("id,user_id,signed_in_at,signed_out_at,last_seen_at,status,end_reason,app_platform,app_version,device_id")
        .order("signed_in_at", { ascending: false })
        .limit(limit);

      if (startIso) q = q.gte("signed_in_at", startIso);
      if (endIso) q = q.lte("signed_in_at", endIso);
      if (filterUser) q = q.eq("user_id", filterUser);

      const { data: sessions, error } = await q;
      if (error) throw error;

      const userIds = Array.from(new Set((sessions ?? []).map((s: any) => String(s.user_id)))).filter(Boolean);
      const profileById = await fetchProfilesByIds(adminClient, userIds);

      const out: any[] = [];
      const now = new Date();
      for (const s of sessions ?? []) {
        const start = new Date((s as any).signed_in_at);
        const end = (s as any).signed_out_at ? new Date((s as any).signed_out_at) : new Date((s as any).last_seen_at);

        const p = profileById.get((s as any).user_id) || {};
        const role = (p.role ?? "").toString();
        if (filterRole && role !== filterRole) continue;

        const providerType = (p.providerType ?? (p as any).provider_type ?? (p as any).providertype ?? null);

        const startIso2 = iso(start);
        const endIso2 = iso(end);

        // Activity is expensive; only compute when requested.
        let activity: any = null;
        if (includeActivity) {
          const testRows = await fetchTestRecordsInWindow(adminClient, (s as any).user_id, startIso2, endIso2);
          let malaria = false;
          let hiv = false;
          const totalsByProgram: Record<string, number> = {};

          if (Array.isArray(testRows)) {
            for (const r of testRows) {
              const prog = normalizeProgram((r as any).program);
              if (prog === "malaria") malaria = true;
              if (prog === "hiv") hiv = true;
              totalsByProgram[prog] = (totalsByProgram[prog] ?? 0) + 1;
            }
          }

          const pmRows = await fetchPreventionRecordsInWindow(adminClient, (s as any).user_id, startIso2, endIso2);
          const prevention = Array.isArray(pmRows) ? pmRows.length > 0 : false;
          if (Array.isArray(pmRows)) totalsByProgram["prevention_messaging"] = pmRows.length;
          activity = {
            malaria,
            hiv,
            preventionMessaging: prevention,
            totalsByProgram,
          };
        }

        const signedOutAt = (s as any).signed_out_at ? new Date((s as any).signed_out_at) : null;
        const durationSeconds = signedOutAt ? Math.max(0, Math.floor((signedOutAt.getTime() - start.getTime()) / 1000)) : null;

        out.push({
          sessionId: (s as any).id,
          userId: (s as any).user_id,
          name: (p.username ?? "").toString(),
          email: (p.contactEmail ?? (p as any).contact_email ?? p.email ?? "").toString(),
          role,
          providerType,
          state: (p.state ?? "").toString(),
          lga: (p.lga ?? "").toString(),
          ward: (p.ward ?? "").toString(),
          signedInAt: (s as any).signed_in_at,
          signedInDate: (s as any).signed_in_at,
          signedOutAt: (s as any).signed_out_at,
          lastSeenAt: (s as any).last_seen_at,
          status: derivedSessionStatus(s, now),
          endReason: (s as any).end_reason,
          durationSeconds,
          appPlatform: (s as any).app_platform,
          appVersion: (s as any).app_version,
          deviceId: (s as any).device_id,
          activity,
        });
      }

      return jsonResponse(200, { ok: true, sessions: out });
    }

    if (action === "summary") {
      const { userId: requesterId } = await requireAuthedUserId(url, anonKey, req);
      await requireSuperAdminFull(adminClient, requesterId);

      const startIso = (body.start ?? "").toString().trim();
      const endIso = (body.end ?? "").toString().trim();

      const [totalSignIns, uniqueAccounts] = await Promise.all([countSessions(adminClient, startIso, endIso), countUniqueUsers(adminClient, startIso, endIso)]);
      return jsonResponse(200, { ok: true, totalSignIns, uniqueAccounts });
    }

    if (action === "get_session_activity") {
      const { userId: requesterId } = await requireAuthedUserId(url, anonKey, req);
      await requireSuperAdminFull(adminClient, requesterId);

      const sessionId = (body.sessionId ?? "").toString().trim();
      if (!sessionId) return jsonResponse(400, { ok: false, error: "sessionId is required" });

      const { data: s, error } = await adminClient
        .from("user_login_sessions")
        .select("id,user_id,signed_in_at,signed_out_at,last_seen_at,status")
        .eq("id", sessionId)
        .maybeSingle();
      if (error) throw error;
      if (!s) return jsonResponse(404, { ok: false, error: "Session not found" });

      const start = new Date((s as any).signed_in_at);
      const end = (s as any).signed_out_at ? new Date((s as any).signed_out_at) : new Date((s as any).last_seen_at);
      const startIso2 = iso(start);
      const endIso2 = iso(end);

      const a = emptyActivity();

      const testRows = await fetchTestRecordsInWindow(adminClient, (s as any).user_id, startIso2, endIso2);
      if (Array.isArray(testRows)) {
        for (const r of testRows) {
          const id = String((r as any).id ?? "").trim();
          const prog = normalizeProgram((r as any).program);
          if (prog === "malaria") {
            a.malariaCount++;
            if (id) a.malariaIds.push(id);
          } else if (prog === "hiv") {
            a.hivCount++;
            if (id) a.hivIds.push(id);
          }
        }
      }

      const pmRows = await fetchPreventionRecordsInWindow(adminClient, (s as any).user_id, startIso2, endIso2);
      if (Array.isArray(pmRows)) {
        a.preventionMessagingCount = pmRows.length;
        for (const r of pmRows) {
          const id = String((r as any).id ?? "").trim();
          if (id) a.preventionMessagingIds.push(id);
        }
      }

      a.totalCount = a.malariaCount + a.hivCount + a.preventionMessagingCount;
      return jsonResponse(200, { ok: true, sessionId, activity: a, start: startIso2, end: endIso2 });
    }

    if (action === "export_csv") {
      const { userId: requesterId } = await requireAuthedUserId(url, anonKey, req);
      await requireSuperAdminFull(adminClient, requesterId);

      const startIso = (body.start ?? "").toString().trim();
      const endIso = (body.end ?? "").toString().trim();
      const filterRole = (body.role ?? "").toString().trim();
      const maxIdsPerProgram = Math.min(50, Math.max(0, safeInt(body.maxIdsPerProgram) || 15));

      // Fetch all sessions in range (paged) so we are NOT limited to the on-screen cap.
      const pageSize = 500;
      const sessions: any[] = [];
      for (let offset = 0; offset < 200000; offset += pageSize) {
        const page = await fetchSessionsInRange(adminClient, startIso, endIso, pageSize, offset);
        sessions.push(...page);
        if (page.length < pageSize) break;
      }

      const userIds = Array.from(new Set(sessions.map((s: any) => String(s.user_id)))).filter(Boolean);
      const profileById = await fetchProfilesByIds(adminClient, userIds);

      // Filter sessions by role (if requested) after we have profiles.
      const filteredSessions: any[] = [];
      for (const s of sessions) {
        const p = profileById.get(String(s.user_id)) || {};
        const role = String(p.role ?? "");
        if (filterRole && role !== filterRole) continue;
        filteredSessions.push(s);
      }

      // Activity reconstruction:
      // We match records to sessions by (user_id + timestamp within session window).
      // If sessions overlap for the same user (rare), we attribute to the newest matching session.
      const now = new Date();
      const sessionMeta = filteredSessions.map((s: any) => {
        const start = new Date(s.signed_in_at);
        const end = s.signed_out_at ? new Date(s.signed_out_at) : new Date(s.last_seen_at);
        return { s, userId: String(s.user_id), start, end };
      });

      const sessionsByUser = new Map<string, Array<{ s: any; start: Date; end: Date }>>();
      for (const m of sessionMeta) {
        if (!sessionsByUser.has(m.userId)) sessionsByUser.set(m.userId, []);
        sessionsByUser.get(m.userId)!.push({ s: m.s, start: m.start, end: m.end });
      }
      for (const [uid, arr] of sessionsByUser.entries()) {
        arr.sort((a, b) => b.start.getTime() - a.start.getTime());
        sessionsByUser.set(uid, arr);
      }

      const activityBySessionId = new Map<string, ActivityCounts>();
      for (const m of sessionMeta) activityBySessionId.set(String(m.s.id), emptyActivity());

      // Pull all candidate records in one pass per table (paged), then bucket them.
      if (userIds.length > 0 && startIso && endIso) {
        const testRows = await fetchAllTestRecordsForUsers(adminClient, userIds, startIso, endIso);
        for (const r of testRows) {
          const uid = chooseUserField(r, ["user_id", "userId", "userid"]);
          const ts = chooseTimeField(r, ["test_date", "testDate", "testdate"]);
          if (!uid || !ts) continue;
          const t = new Date(ts);
          const sessionsForUser = sessionsByUser.get(uid);
          if (!sessionsForUser) continue;
          const matched = sessionsForUser.find((m) => t.getTime() >= m.start.getTime() && t.getTime() <= m.end.getTime());
          if (!matched) continue;
          const sid = String(matched.s.id);
          const a = activityBySessionId.get(sid);
          if (!a) continue;
          const id = String((r as any).id ?? "").trim();
          const prog = normalizeProgram((r as any).program);
          if (prog === "malaria") {
            a.malariaCount++;
            if (id) a.malariaIds.push(id);
          } else if (prog === "hiv") {
            a.hivCount++;
            if (id) a.hivIds.push(id);
          }
        }

        const pmRows = await fetchAllPreventionRecordsForUsers(adminClient, userIds, startIso, endIso);
        for (const r of pmRows) {
          const uid = chooseUserField(r, ["user_id", "userId", "userid"]);
          const ts = chooseTimeField(r, ["created_at", "createdAt", "createdat"]);
          if (!uid || !ts) continue;
          const t = new Date(ts);
          const sessionsForUser = sessionsByUser.get(uid);
          if (!sessionsForUser) continue;
          const matched = sessionsForUser.find((m) => t.getTime() >= m.start.getTime() && t.getTime() <= m.end.getTime());
          if (!matched) continue;
          const sid = String(matched.s.id);
          const a = activityBySessionId.get(sid);
          if (!a) continue;
          const id = String((r as any).id ?? "").trim();
          a.preventionMessagingCount++;
          if (id) a.preventionMessagingIds.push(id);
        }
      }

      for (const a of activityBySessionId.values()) {
        a.totalCount = a.malariaCount + a.hivCount + a.preventionMessagingCount;
      }

      const header = [
        "session_id",
        "user_id",
        "name",
        "email_or_username",
        "role",
        "provider_type",
        "state",
        "lga",
        "ward",
        "signed_in_date",
        "signed_in_time",
        "signed_out_time",
        "session_duration_seconds",
        "last_seen_time",
        "session_status",
        "end_reason",
        "malaria_records_created",
        "hiv_records_created",
        "prevention_messaging_records_created",
        "total_records_created",
        "malaria_record_ids",
        "hiv_record_ids",
        "prevention_messaging_record_ids",
        "app_platform",
        "app_version",
        "device_id",
      ].join(",");

      const lines: string[] = [header];

      // Keep newest first (same as UI).
      filteredSessions.sort((a, b) => new Date(b.signed_in_at).getTime() - new Date(a.signed_in_at).getTime());

      for (const s of filteredSessions) {
        const p = profileById.get(String(s.user_id)) || {};
        const status = derivedSessionStatus(s, now);
        const signedInAt = String(s.signed_in_at ?? "");
        const signedOutAt = s.signed_out_at ? String(s.signed_out_at) : "";
        const lastSeenAt = String(s.last_seen_at ?? "");
        const start = new Date(signedInAt);
        const end = signedOutAt ? new Date(signedOutAt) : new Date(lastSeenAt);
        const durationSeconds = signedOutAt ? Math.max(0, Math.floor((end.getTime() - start.getTime()) / 1000)) : "";

        const a = activityBySessionId.get(String(s.id)) ?? emptyActivity();

        const name = String(p.name ?? p.full_name ?? p.fullName ?? p.username ?? "");
        const email = String(p.contactEmail ?? p.contact_email ?? p.email ?? p.username ?? "");
        const role = String(p.role ?? "");
        const providerType = String(p.providerType ?? (p as any).provider_type ?? (p as any).providertype ?? "");
        const state = String(p.state ?? "");
        const lga = String(p.lga ?? "");
        const ward = String(p.ward ?? "");

        lines.push(
          [
            csvEscape(String(s.id)),
            csvEscape(String(s.user_id)),
            csvEscape(name),
            csvEscape(email),
            csvEscape(role),
            csvEscape(providerType),
            csvEscape(state),
            csvEscape(lga),
            csvEscape(ward),
            csvEscape(fmtDateLocal(signedInAt)),
            csvEscape(fmtTimeLocal(signedInAt)),
            csvEscape(fmtTimeLocal(signedOutAt)),
            csvEscape(durationSeconds),
            csvEscape(fmtTimeLocal(lastSeenAt)),
            csvEscape(status),
            csvEscape(String(s.end_reason ?? "")),
            csvEscape(a.malariaCount),
            csvEscape(a.hivCount),
            csvEscape(a.preventionMessagingCount),
            csvEscape(a.totalCount),
            csvEscape(compactIds(a.malariaIds, maxIdsPerProgram)),
            csvEscape(compactIds(a.hivIds, maxIdsPerProgram)),
            csvEscape(compactIds(a.preventionMessagingIds, maxIdsPerProgram)),
            csvEscape(String(s.app_platform ?? "")),
            csvEscape(String(s.app_version ?? "")),
            csvEscape(String(s.device_id ?? "")),
          ].join(","),
        );
      }

      const csv = lines.join("\n");
      const filename = `login_tracker_${fmtDateLocal(startIso || iso(new Date()))}_to_${fmtDateLocal(endIso || iso(new Date()))}.csv`;
      return jsonResponse(200, { ok: true, filename, csv, rowCount: filteredSessions.length });
    }

    return jsonResponse(400, { ok: false, error: "Unknown action" });
  } catch (e) {
    const msg = String((e as any)?.message ?? e);
    return jsonResponse(500, { ok: false, error: "Request failed", details: msg });
  }
});
