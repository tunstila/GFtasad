import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-max-age": "86400",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, "content-type": "application/json" } });
}

function asString(v: unknown) {
  return typeof v === "string" ? v : "";
}

function normalizeEmail(v: unknown) {
  const s = asString(v).trim().toLowerCase();
  return s;
}

function normalizeUsername(v: unknown) {
  const s = asString(v).trim().toLowerCase();
  return s;
}

function normalizeNullableText(v: unknown) {
  const s = asString(v).trim();
  return s.length ? s : null;
}

function normalizeProviderType(v: unknown) {
  const raw = asString(v).trim();
  if (!raw) return null;
  const cleaned = raw.toLowerCase().replace(/[^a-z]/g, "");
  if (cleaned === "ppmv") return "ppmv";
  if (cleaned === "cp") return "cp";
  if (cleaned === "chp") return "chp";
  throw new Error("Invalid providerType");
}

function normalizeApprovalStatus(v: unknown) {
  const raw = asString(v).trim().toLowerCase();
  if (!raw) return null;
  if (!["pending", "approved", "rejected"].includes(raw)) throw new Error("Invalid approvalStatus");
  return raw as "pending" | "approved" | "rejected";
}

function looksLikeEmail(v: string) {
  return v.includes("@");
}

async function getRequester(dbUser: any, requesterId: string) {
  const { data, error } = await dbUser
    .from("users")
    .select("id,role,adminScope,email")
    .eq("id", requesterId)
    .maybeSingle();
  if (error) throw error;
  return data as any;
}

function isSuperAdminFull(requester: any) {
  const role = asString(requester?.role).trim();
  const scope = asString(requester?.adminScope).trim();
  const email = normalizeEmail(requester?.email);
  // Keep bootstrap escape hatch aligned with Flutter AuthService.
  if (email === "tundeoyelana@gmail.com") return true;
  if (role === "superAdmin") return true;
  if (scope === "full") return true;
  return false;
}

async function getTargetUser(dbAdmin: any, targetUserId: string) {
  const { data, error } = await dbAdmin
    .from("users")
    .select("id,role,username,email,contactEmail,isSyntheticAuthEmail,approvalStatus")
    .eq("id", targetUserId)
    .maybeSingle();
  if (error) throw error;
  return data as any;
}

function buildProfileUpdates(patch: any) {
  const updates: Record<string, unknown> = {};
  if ("state" in patch) updates.state = normalizeNullableText(patch.state);
  if ("lga" in patch) updates.lga = normalizeNullableText(patch.lga);
  if ("facilityName" in patch) updates.facilityName = normalizeNullableText(patch.facilityName);
  if ("businessAddress" in patch) updates.businessAddress = normalizeNullableText(patch.businessAddress);
  if ("contactEmail" in patch) {
    const c = normalizeNullableText(patch.contactEmail);
    updates.contactEmail = c ? c.toLowerCase() : null;
  }
  if ("providerType" in patch) updates.providerType = normalizeProviderType(patch.providerType);
  if ("latitude" in patch) updates.latitude = patch.latitude === null || patch.latitude === "" ? null : Number(patch.latitude);
  if ("longitude" in patch) updates.longitude = patch.longitude === null || patch.longitude === "" ? null : Number(patch.longitude);
  return updates;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const authHeader = req.headers.get("authorization") ?? "";
    const jwt = authHeader.toLowerCase().startsWith("bearer ") ? authHeader.slice(7) : "";
    if (!jwt) return json({ ok: false, error: "Missing Authorization header" }, 401);

    // User-scoped client (RLS-respecting) used only to fetch requester identity.
    const dbUser = createClient(url, anonKey, { global: { headers: { Authorization: `Bearer ${jwt}` } } });
    const { data: authed, error: authedErr } = await dbUser.auth.getUser();
    if (authedErr || !authed?.user) return json({ ok: false, error: "Invalid session" }, 401);

    const requesterId = authed.user.id;

    // Admin client (service role) for privileged checks and updates.
    const dbAdmin = createClient(url, serviceRoleKey);

    const requester = await getRequester(dbAdmin, requesterId);
    if (!isSuperAdminFull(requester)) return json({ ok: false, error: "Forbidden" }, 403);

    const payload = await req.json().catch(() => ({}));
    const targetUserId = asString(payload.targetUserId || payload.userId || payload.targetUserId).trim();
    if (!targetUserId) return json({ ok: false, error: "targetUserId is required" }, 400);

    const patch = (payload.patch && typeof payload.patch === "object") ? payload.patch : payload;

    const target = await getTargetUser(dbAdmin, targetUserId);
    if (!target?.id) return json({ ok: false, error: "Target user not found" }, 404);
    if (asString(target.role).trim() !== "fieldProvider") return json({ ok: false, error: "Target user is not a fieldProvider" }, 400);

    const oldUsername = asString(target.username);
    const oldEmail = normalizeEmail(target.email);
    const oldApproval = asString(target.approvalstatus || target.approvalStatus || target.approval_status).trim().toLowerCase();

    const nextUsername = ("username" in patch) ? normalizeUsername(patch.username) : null;
    const nextEmail = ("email" in patch) ? normalizeEmail(patch.email) : null;
    const nextApproval = ("approvalstatus" in patch || "approvalStatus" in patch || "approval_status" in patch)
      ? normalizeApprovalStatus((patch as any).approvalstatus ?? patch.approvalStatus ?? patch.approval_status)
      : null;

    // Validation: email format if provided.
    if (nextEmail !== null) {
      if (!looksLikeEmail(nextEmail)) return json({ ok: false, error: "Invalid email" }, 400);
    }

    // Uniqueness checks (case-insensitive) when identity changes.
    if (nextUsername !== null && nextUsername !== normalizeUsername(oldUsername)) {
      const { data: existingU, error: existingUErr } = await dbAdmin
        .from("users")
        .select("id")
        .ilike("username", nextUsername)
        .neq("id", targetUserId)
        .maybeSingle();
      if (existingUErr) throw existingUErr;
      if (existingU?.id) return json({ ok: false, error: "Username already in use" }, 409);
    }

    if (nextEmail !== null && nextEmail !== oldEmail) {
      const { data: existingE, error: existingEErr } = await dbAdmin
        .from("users")
        .select("id")
        .filter("email", "ilike", nextEmail)
        .neq("id", targetUserId)
        .maybeSingle();
      if (existingEErr) throw existingEErr;
      if (existingE?.id) return json({ ok: false, error: "Email already in use" }, 409);
    }

    const profileUpdates = buildProfileUpdates(patch);

    const userRowUpdates: Record<string, unknown> = {
      ...profileUpdates,
      updatedAt: new Date().toISOString(),
      updatedBy: requesterId,
    };

    if (nextUsername !== null) userRowUpdates.username = nextUsername;
    if (nextEmail !== null) userRowUpdates.email = nextEmail;

    // Approval updates + audit fields.
    if (nextApproval !== null && nextApproval !== oldApproval) {
      userRowUpdates.approvalstatus = nextApproval;
      if (nextApproval === "approved" || nextApproval === "rejected") {
        userRowUpdates.approvedat = new Date().toISOString();
        userRowUpdates.approvedby = requesterId;
      }
      if (nextApproval === "pending") {
        userRowUpdates.approvedat = null;
        userRowUpdates.approvedby = null;
      }
    }

    // Auth-linked updates: email changes must also update auth.users.
    // Username changes are login-critical (used by sign_in_with_identifier), so force this through this function.
    let authEmailUpdated = false;

    if (nextEmail !== null && nextEmail !== oldEmail) {
      const authRes = await dbAdmin.auth.admin.updateUserById(targetUserId, { email: nextEmail });
      if (authRes.error) return json({ ok: false, error: `Failed to update auth email: ${authRes.error.message}` }, 400);
      authEmailUpdated = true;
    }

    // Update profile row.
    const { data: updated, error: updErr } = await dbAdmin
      .from("users")
      .update(userRowUpdates)
      .eq("id", targetUserId)
      .select("*")
      .maybeSingle();

    if (updErr) {
      // Compensation attempt if we already updated auth email.
      if (authEmailUpdated) {
        try {
          await dbAdmin.auth.admin.updateUserById(targetUserId, { email: oldEmail });
        } catch (_e) {
          // best-effort only
        }
      }
      return json({ ok: false, error: `Failed to update profile: ${updErr.message}` }, 400);
    }

    return json({
      ok: true,
      user: updated,
      applied: {
        emailChanged: nextEmail !== null && nextEmail !== oldEmail,
        usernameChanged: nextUsername !== null && nextUsername !== normalizeUsername(oldUsername),
        approvalChanged: nextApproval !== null && nextApproval !== oldApproval,
        profileFieldsChanged: Object.keys(profileUpdates).length > 0,
      },
    });
  } catch (e) {
    const msg = (e as any)?.message ?? String(e);
    return json({ ok: false, error: msg }, 500);
  }
});
