// Supabase Edge Function: admin_user_management
// - Notifies super admins on pending signup
// - Lets super admins approve users and assign admin scopes
// - Lists users for admin review
// - Creates users (super admin creates account + generated password)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-max-age": "86400",
};

const SUPER_ADMIN_BOOTSTRAP_EMAIL = "tundeoyelana@gmail.com";

type AdminScope = "none" | "viewOnly" | "full";

type Action =
  | "ping"
  | "notify_pending_signup"
  | "list_users"
  | "approve_user"
  | "set_admin_scope"
  | "update_user"
  | "create_user"
  | "reset_password";

type UserRole =
  | "fieldProvider"
  | "supplier"
  | "stateMalaria"
  | "stateHIVTB"
  | "nationalMalaria"
  | "nationalHIVTB"
  | "sfhTeam"
  | "superAdmin";

type ApprovalStatus = "pending" | "approved" | "rejected";

class HttpError extends Error {
  status: number;
  code: string;
  details?: Record<string, unknown>;

  constructor(status: number, code: string, message: string, details?: Record<string, unknown>) {
    super(message);
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "content-type": "application/json" },
  });
}

function asErrorMessage(e: unknown): string {
  const anyE = e as any;
  return (anyE?.message as string | undefined) ?? String(e);
}

function missingColumnFromMessage(msg: string): string | null {
  // Typical PostgREST messages:
  // - Could not find the 'createdAt' column of 'deliveries' in the schema cache
  // - column users.facilityName does not exist
  const m1 = msg.match(/Could not find the '([^']+)' column/i);
  if (m1?.[1]) return m1[1];
  const m2 = msg.match(/column\s+[^.]+\.([^\s]+)\s+does not exist/i);
  if (m2?.[1]) return m2[1];
  return null;
}

async function resilientUpsert(db: any, table: string, row: Record<string, unknown>, onConflict: string) {
  const working: Record<string, unknown> = { ...row };
  Object.keys(working).forEach((k) => working[k] === null || working[k] === undefined ? delete working[k] : null);

  for (let attempt = 0; attempt < 12; attempt++) {
    const res = await (db.from(table) as any).upsert(working as any, { onConflict });
    if (!res.error) return;
    const msg = asErrorMessage(res.error);
    const missing = missingColumnFromMessage(msg);
    if (!missing || !(missing in working)) throw res.error;
    console.error(`Schema mismatch (upsert ${table}): removing missing column '${missing}' and retrying`);
    delete working[missing];
  }
  throw new Error(`Resilient upsert exceeded retries for table=${table}`);
}

async function resilientUpdate(db: any, table: string, updates: Record<string, unknown>, filters: Record<string, unknown>) {
  const working: Record<string, unknown> = { ...updates };
  Object.keys(working).forEach((k) => working[k] === null || working[k] === undefined ? delete working[k] : null);

  for (let attempt = 0; attempt < 12; attempt++) {
    let q: any = (db.from(table) as any).update(working as any);
    for (const [k, v] of Object.entries(filters)) q = q.eq(k, v);
    const res = await q;
    if (!res.error) return;
    const msg = asErrorMessage(res.error);
    const missing = missingColumnFromMessage(msg);
    if (!missing || !(missing in working)) throw res.error;
    console.error(`Schema mismatch (update ${table}): removing missing column '${missing}' and retrying`);
    delete working[missing];
  }
  throw new Error(`Resilient update exceeded retries for table=${table}`);
}

function normalizeEmail(email: unknown) {
  const e = typeof email === "string" ? email.trim().toLowerCase() : "";
  return e;
}

function normalizeUsername(username: unknown) {
  return typeof username === "string" ? username.trim().toLowerCase() : "";
}

function isValidUsername(usernameNormalized: string) {
  // Letters, numbers, underscore, dot. 3-24 chars.
  return /^[a-z0-9_.]{3,24}$/.test(usernameNormalized);
}

function makeSyntheticAuthEmail(userId: string) {
  // Non-routable, internal-only. Must still be a valid email string for Supabase auth.
  return `${userId}@auth.local.invalid`;
}

function generatePassword(length = 14) {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
  const symbols = "!@#$%*?";
  const all = alphabet + symbols;

  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);

  let out = "";
  for (let i = 0; i < bytes.length; i++) {
    out += all[bytes[i] % all.length];
  }

  // Ensure at least 1 symbol for strength.
  if (!out.split("").some((c) => symbols.includes(c))) {
    out = out.slice(0, out.length - 1) + symbols[bytes[0] % symbols.length];
  }

  return out;
}

async function sendEmail(params: { to: string[]; subject: string; html: string }) {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  const fromEmail = Deno.env.get("FROM_EMAIL");
  if (!apiKey || !fromEmail) {
    throw new Error("Missing RESEND_API_KEY or FROM_EMAIL env var");
  }

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: fromEmail,
      to: params.to,
      subject: params.subject,
      html: params.html,
    }),
  });

  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`Resend error: ${res.status} ${txt}`);
  }

  return await res.json();
}

// Supabase Edge Functions expect a Deno.serve() entrypoint.
// Using Deno.serve also guarantees requests are actually handled after deploy.
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const adminDb = createClient(url, serviceRoleKey);

    const payload = await req.json().catch(() => ({}));
    const action = payload.action as Action | undefined;

    if (!action) return json({ ok: false, error: "Missing action" }, 400);

    if (action === "ping") {
      // Lightweight health check to validate deployment + CORS + JWT wiring.
      return json({ ok: true, now: new Date().toISOString() });
    }

    // Helper: validate requester for privileged actions
    const authHeader = req.headers.get("Authorization");
    const userDb = authHeader
      ? createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } })
      : null;

    async function safeGetAuthUser() {
      if (!userDb) {
        throw new HttpError(
          401,
          "missing_auth",
          "Missing Authorization header. Please sign in again and retry.",
        );
      }
      const { data: userData, error: userErr } = await userDb.auth.getUser();
      if (userErr || !userData.user) {
        throw new HttpError(401, "invalid_auth", "Invalid or expired session. Please sign in again and retry.");
      }
      return userData.user;
    }

    async function getRequesterProfile(requesterId: string) {
      // This app uses `public.users` as its profile table.
      // Some older iterations tried `public.profiles`, but in your DB that table does not exist
      // and will trigger a PostgREST schema-cache error.
      const { data, error } = await adminDb.from("users").select("*").eq("id", requesterId).maybeSingle();
      if (error) {
        console.error("Requester profile lookup failed for table=users", error);
        return null;
      }
      return data ? { table: "users" as const, profile: data as any } : null;
    }

    function readProfileField<T = unknown>(profile: any, camel: string, snake: string): T | null {
      if (!profile || typeof profile !== "object") return null;
      const v1 = profile[camel];
      if (v1 !== undefined && v1 !== null) return v1 as T;
      const v2 = profile[snake];
      if (v2 !== undefined && v2 !== null) return v2 as T;
      return null;
    }

    async function upsertBootstrapProfile(requesterId: string, requesterEmail: string, authUser: any) {
      const now = new Date().toISOString();

  // Attempt camelCase first (matches this Flutter repo), then snake_case for older schemas.
  // IMPORTANT: Some databases may not have *any* admin-scope column (adminScope/admin_scope).
  // So we avoid requiring it for bootstrap.
      const seedRowCamel = {
        id: requesterId,
        email: requesterEmail,
        username: (authUser.user_metadata?.username as string | undefined) ?? "Super Admin",
        role: "superAdmin",
        approvalStatus: "approved",
        approvedAt: now,
        approvedBy: requesterId,
        forcePasswordChange: false,
        createdAt: now,
        updatedAt: now,
      };

      const seedRowSnake = {
        id: requesterId,
        email: requesterEmail,
        username: (authUser.user_metadata?.username as string | undefined) ?? "Super Admin",
        role: "superAdmin",
        approval_status: "approved",
        approved_at: now,
        approved_by: requesterId,
        force_password_change: false,
        created_at: now,
        updated_at: now,
      };

      // Minimal variants: some schemas may not have approval/forcePasswordChange columns.
      const seedRowCamelMinimal = {
        id: requesterId,
        email: requesterEmail,
        username: (authUser.user_metadata?.username as string | undefined) ?? "Super Admin",
        role: "superAdmin",
        createdAt: now,
        updatedAt: now,
      };

      const seedRowSnakeMinimal = {
        id: requesterId,
        email: requesterEmail,
        username: (authUser.user_metadata?.username as string | undefined) ?? "Super Admin",
        role: "superAdmin",
        created_at: now,
        updated_at: now,
      };

      const seedRowMinimalMinimal = {
        id: requesterId,
        email: requesterEmail,
        username: (authUser.user_metadata?.username as string | undefined) ?? "Super Admin",
        role: "superAdmin",
      };

      const targetTables = ["users"] as const;
      const candidates = [seedRowCamel, seedRowSnake, seedRowCamelMinimal, seedRowSnakeMinimal, seedRowMinimalMinimal];

      for (const table of targetTables) {
        for (const row of candidates) {
          try {
            await resilientUpsert(adminDb, table, row as any, "id");
            return { table };
          } catch (e) {
            console.error(`Failed to seed bootstrap admin profile in table=${table}`, e);
          }
        }
      }

      return null;
    }

    async function upsertNewUserProfile(params: {
      userId: string;
      username: string;
      authEmail: string;
      contactEmail?: string | null;
      isSyntheticAuthEmail?: boolean;
      role: string;
      facilityName?: string | null;
      providerType?: string | null;
      lga?: string | null;
      state?: string | null;
      requesterId: string;
      adminScope: AdminScope;
    }) {
      const now = new Date().toISOString();

      // This app's profile table is `public.users`.
      // Do NOT try `public.profiles` here — if it doesn't exist, PostgREST returns
      // "Could not find the table `public.profiles` in the schema cache" and masks the
      // real error for the actual table.
      const targetTables = ["users"] as const;

      // Some schemas use `full_name` instead of `username`.
      // Some schemas enforce NOT NULL constraints; include both variants where possible.

  // NOTE: adminScope/admin_scope is optional across environments.
  // We prefer profile creation to succeed even if that column doesn't exist.
  const rowCamel = {
        id: params.userId,
        username: params.username,
        fullName: params.username,
        email: params.authEmail,
        contactEmail: params.contactEmail ?? null,
        isSyntheticAuthEmail: params.isSyntheticAuthEmail ?? false,
        role: params.role,
        facilityName: params.facilityName ?? null,
        providerType: params.providerType ?? null,
        lga: params.lga ?? null,
        state: params.state ?? null,
        forcePasswordChange: true,
        approvalStatus: "approved",
        approvedAt: now,
        approvedBy: params.requesterId,
        createdAt: now,
        updatedAt: now,
      };

      const rowSnake = {
        id: params.userId,
        username: params.username,
        full_name: params.username,
        email: params.authEmail,
        contact_email: params.contactEmail ?? null,
        is_synthetic_auth_email: params.isSyntheticAuthEmail ?? false,
        role: params.role,
        facility_name: params.facilityName ?? null,
        provider_type: params.providerType ?? null,
        lga: params.lga ?? null,
        state: params.state ?? null,
        force_password_change: true,
        approval_status: "approved",
        approved_at: now,
        approved_by: params.requesterId,
        created_at: now,
        updated_at: now,
      };

  const rowCamelMinimal = {
        id: params.userId,
        username: params.username,
        fullName: params.username,
        email: params.authEmail,
        contactEmail: params.contactEmail ?? null,
        isSyntheticAuthEmail: params.isSyntheticAuthEmail ?? false,
        role: params.role,
        createdAt: now,
        updatedAt: now,
      };

      const rowSnakeMinimal = {
        id: params.userId,
        username: params.username,
        full_name: params.username,
        email: params.authEmail,
        contact_email: params.contactEmail ?? null,
        is_synthetic_auth_email: params.isSyntheticAuthEmail ?? false,
        role: params.role,
        created_at: now,
        updated_at: now,
      };

  // Optional variants that include admin-scope fields (only if the column exists).
  const rowCamelWithScope = { ...rowCamelMinimal, adminScope: params.adminScope } as any;
  const rowSnakeWithScope = { ...rowSnakeMinimal, admin_scope: params.adminScope } as any;

      const rowMinimalMinimal = {
        id: params.userId,
        email: params.authEmail,
        username: params.username,
        role: params.role,
      };

      // Try no-scope variants first to avoid failing on missing adminScope/admin_scope.
      const candidates = [
        rowCamel,
        rowSnake,
        rowCamelMinimal,
        rowSnakeMinimal,
        rowMinimalMinimal,
        rowCamelWithScope,
        rowSnakeWithScope,
      ];

      let firstUsersError: any = null;
      for (const table of targetTables) {
        for (const row of candidates) {
          try {
            await resilientUpsert(adminDb, table, row as any, "id");
            return { table };
          } catch (e) {
            if (!firstUsersError) firstUsersError = e;
            console.error(`Failed to upsert new user profile in table=${table}`, e);
          }
        }
      }

      return { table: null as any, error: firstUsersError };
    }

    async function requireAdmin(minScope: "view" | "full") {
      const authUser = await safeGetAuthUser();
      const requesterId = authUser.id;

      const found = await getRequesterProfile(requesterId);

      const requesterEmail = (authUser.email ?? "").trim().toLowerCase();
      const isBootstrap = requesterEmail === SUPER_ADMIN_BOOTSTRAP_EMAIL.toLowerCase();

      // Auto-bootstrap the very first super admin profile if it's missing.
      // This avoids a deadlock where the only super admin can never create users
      // because their profile row was never inserted.
      if (!found) {
        if (!isBootstrap) {
          throw new HttpError(
            403,
            "requester_profile_missing",
            "Admin profile missing. Ask a Super Admin to approve you, or create a row in `public.users` for your auth user id.",
            { requesterId },
          );
        }

        const seeded = await upsertBootstrapProfile(requesterId, requesterEmail, authUser);
        if (!seeded) {
          throw new HttpError(
            500,
            "bootstrap_seed_failed",
            "Super Admin bootstrap profile was missing and could not be created automatically.",
            { requesterId },
          );
        }
      }

      const resolved = found ?? (await getRequesterProfile(requesterId));
      if (!resolved) {
        throw new HttpError(
          403,
          "requester_profile_missing",
          "Admin profile missing. Please sign out, sign in, then retry. If this persists, contact support.",
          { requesterId },
        );
      }

      const profile = resolved.profile;
      const emailFromProfile = (((profile.email as string | null) ?? requesterEmail) as string).toLowerCase();
      const scope = (readProfileField<string>(profile, "adminScope", "admin_scope") as AdminScope | null) ?? "none";
      const role = (readProfileField<string>(profile, "role", "role") as UserRole | null) ?? null;

      // Allow either adminScope OR role to grant access.
      const hasView = isBootstrap || scope === "viewOnly" || scope === "full" || role === "superAdmin";
      const hasFull = isBootstrap || scope === "full" || role === "superAdmin";

      if (minScope === "view" && !hasView) {
        throw new HttpError(403, "forbidden", "You do not have permission to perform this action.");
      }
      if (minScope === "full" && !hasFull) {
        throw new HttpError(403, "forbidden", "Only Super Admin can create or approve users.");
      }

      return { requesterId, requesterEmail: emailFromProfile, isBootstrap, scope };
    }

    if (action === "notify_pending_signup") {
      const userId = payload.userId as string | undefined;
      if (!userId) return json({ ok: false, error: "Missing userId" }, 400);

      // Use '*' to avoid schema-cache failures when a column is missing.
      const { data: newUser, error: newUserErr } = await adminDb.from("users").select("*").eq("id", userId).maybeSingle();

      if (newUserErr || !newUser) return json({ ok: false, error: "User not found" }, 404);

      const { data: admins, error: adminsErr } = await adminDb
        .from("users")
        .select("email")
        // Do not rely on adminScope/admin_scope existing in the DB.
        // We consider `role=superAdmin` as the source of truth for super-admin privileges.
        .or("role.eq.superAdmin,email.eq." + SUPER_ADMIN_BOOTSTRAP_EMAIL);

      if (adminsErr) throw adminsErr;

      const adminEmails = Array.from(
        new Set(
          (admins ?? [])
            .map((a: any) => (a.email as string | null)?.trim())
            .filter((e: string | null | undefined) => typeof e === "string" && e.length > 0),
        ),
      ) as string[];

      if (adminEmails.length === 0) {
        return json({ ok: true, warned: "No super admin emails found" });
      }

      const safeFacility =
        ((newUser as any)?.facilityName as string | null) ?? ((newUser as any)?.facility_name as string | null) ?? "";
      const html = `
        <div style="font-family:Inter,system-ui,Segoe UI,Roboto,Arial;line-height:1.5">
          <h2>MediFlow: New signup pending approval</h2>
          <p><b>User:</b> ${newUser.username}</p>
          <p><b>Email:</b> ${newUser.email}</p>
          <p><b>Role:</b> ${newUser.role}</p>
          ${safeFacility ? `<p><b>Facility/Org:</b> ${safeFacility}</p>` : ""}
          <p>Please open the MediFlow Admin panel to approve this account.</p>
        </div>
      `;

      await sendEmail({ to: adminEmails, subject: "MediFlow: Signup approval requested", html });

      return json({ ok: true, notified: adminEmails.length });
    }

    if (action === "list_users") {
      await requireAdmin("view");

      // Use '*' + client-side normalization to avoid hard failing when columns differ.
      // (Your logs show e.g. facilityName/approvalStatus/createdAt missing.)
      const { data, error } = await adminDb.from("users").select("*");

      if (error) throw error;

      // Normalize to the Flutter app's expected camelCase keys where possible.
      const users = (data ?? []).map((u: any) => ({
        id: u.id,
        username: u.username ?? u.full_name ?? u.fullName,
        email: u.email,
        contactEmail: u.contactEmail ?? u.contact_email,
        isSyntheticAuthEmail: u.isSyntheticAuthEmail ?? u.is_synthetic_auth_email,
        role: u.role,
        facilityName: u.facilityName ?? u.facility_name,
        providerType: u.providerType ?? u.provider_type,
        lga: u.lga,
        state: u.state,
        forcePasswordChange: u.forcePasswordChange ?? u.force_password_change,
        lastLogin: u.lastLogin ?? u.last_login,
        approvalStatus: u.approvalStatus ?? u.approval_status,
        approvedAt: u.approvedAt ?? u.approved_at,
        approvedBy: u.approvedBy ?? u.approved_by,
        adminScope: u.adminScope ?? u.admin_scope,
        createdAt: u.createdAt ?? u.created_at,
        updatedAt: u.updatedAt ?? u.updated_at,
      }));

      return json({ ok: true, users });
    }

    if (action === "approve_user") {
      const { requesterId } = await requireAdmin("full");
      const userId = payload.userId as string | undefined;
      if (!userId) return json({ ok: false, error: "Missing userId" }, 400);

      const now = new Date().toISOString();
      try {
        await resilientUpdate(
          adminDb,
          "users",
          {
            approvalStatus: "approved",
            approval_status: "approved",
            approvedAt: now,
            approved_at: now,
            approvedBy: requesterId,
            approved_by: requesterId,
            updatedAt: now,
            updated_at: now,
          } as any,
          { id: userId },
        );
      } catch (e) {
        console.error("Approval update failed", e);
        return json({ ok: false, error: "Approval update failed", code: "approval_update_failed" }, 400);
      }

      const { data: updated, error: fetchErr } = await adminDb.from("users").select("*").eq("id", userId).maybeSingle();
      if (fetchErr || !updated) return json({ ok: true, warned: "approved_but_fetch_failed" });

      const html = `
        <div style="font-family:Inter,system-ui,Segoe UI,Roboto,Arial;line-height:1.5">
          <h2>Your MediFlow account has been approved</h2>
          <p>Hello ${updated.username},</p>
          <p>Your signup request has been authorized. You can now sign in to MediFlow.</p>
        </div>
      `;

      if (updated.email) await sendEmail({ to: [updated.email], subject: "MediFlow: Your account is approved", html });

      return json({ ok: true });
    }

    if (action === "set_admin_scope") {
      await requireAdmin("full");

      const userId = payload.userId as string | undefined;
      const adminScope = payload.adminScope as AdminScope | undefined;
      if (!userId || !adminScope) return json({ ok: false, error: "Missing userId/adminScope" }, 400);

      if (!(["none", "viewOnly", "full"] as string[]).includes(adminScope)) {
        return json({ ok: false, error: "Invalid adminScope" }, 400);
      }

      // Best-effort: some environments do not have adminScope/admin_scope.
      // We try both, and if neither exists, we still return ok (scope is effectively ignored).
      const now = new Date().toISOString();
      try {
        await resilientUpdate(
          adminDb,
          "users",
          { adminScope, admin_scope: adminScope, updatedAt: now, updated_at: now } as any,
          { id: userId },
        );
        return json({ ok: true, persisted: true });
      } catch (e) {
        console.error("set_admin_scope failed (ignored)", e);
        return json({ ok: true, persisted: false, warned: "admin_scope_column_missing" });
      }
    }

    if (action === "update_user") {
      const { requesterId } = await requireAdmin("full");

      const userId = payload.userId as string | undefined;
      const role = payload.role as UserRole | undefined;
      const adminScope = payload.adminScope as AdminScope | undefined;
      const approvalStatus = payload.approvalStatus as ApprovalStatus | undefined;

      if (!userId) return json({ ok: false, error: "Missing userId" }, 400);
      if (!role && !adminScope && !approvalStatus) {
        return json({ ok: false, error: "Nothing to update" }, 400);
      }

      if (
        role &&
        !([
          "fieldProvider",
          "supplier",
          "stateMalaria",
          "stateHIVTB",
          "nationalMalaria",
          "nationalHIVTB",
          "sfhTeam",
          "superAdmin",
        ] as string[]).includes(role)
      ) {
        return json({ ok: false, error: "Invalid role" }, 400);
      }

      if (adminScope && !(["none", "viewOnly", "full"] as string[]).includes(adminScope)) {
        return json({ ok: false, error: "Invalid adminScope" }, 400);
      }

      if (approvalStatus && !(["pending", "approved", "rejected"] as string[]).includes(approvalStatus)) {
        return json({ ok: false, error: "Invalid approvalStatus" }, 400);
      }

      // Protect bootstrap super admin from being locked out by mistake.
      const { data: existing, error: existingErr } = await adminDb.from("users").select("*").eq("id", userId).maybeSingle();
      if (existingErr || !existing) return json({ ok: false, error: "User not found" }, 404);

      const emailLower = ((existing.email as string | null) ?? "").toLowerCase();
      const isBootstrapTarget = emailLower === SUPER_ADMIN_BOOTSTRAP_EMAIL.toLowerCase();

      const now = new Date().toISOString();
      const baseUpdates: Record<string, unknown> = { updatedAt: now, updated_at: now };

      if (!isBootstrapTarget) {
        if (role) baseUpdates.role = role;
        if (approvalStatus) {
          baseUpdates.approvalStatus = approvalStatus;
          baseUpdates.approval_status = approvalStatus;
        }

        if (approvalStatus === "approved") {
          baseUpdates.approvedAt = now;
          baseUpdates.approved_at = now;
          baseUpdates.approvedBy = requesterId;
          baseUpdates.approved_by = requesterId;
        }
      } else {
        // Protect bootstrap super admin from being locked out.
        baseUpdates.approvalStatus = "approved";
        baseUpdates.approval_status = "approved";
      }

      // Best-effort admin scope persistence.
      // We cannot include unknown columns in the same update payload, otherwise PostgREST fails.
      const desiredScope = isBootstrapTarget ? ("full" as AdminScope) : adminScope;

      try {
        await resilientUpdate(
          adminDb,
          "users",
          {
            ...baseUpdates,
            ...(desiredScope ? { adminScope: desiredScope, admin_scope: desiredScope } : {}),
          } as any,
          { id: userId },
        );
      } catch (e) {
        console.error("Update failed", e);
        return json({ ok: false, error: "Update failed", code: "update_failed" }, 400);
      }

      const { data: updated, error: updErr } = await adminDb.from("users").select("*").eq("id", userId).maybeSingle();
      if (updErr || !updated) return json({ ok: true, warned: "updated_but_fetch_failed" });

      // Email user when approval is granted.
      if (!isBootstrapTarget && approvalStatus === "approved" && updated.email) {
        const html = `
          <div style="font-family:Inter,system-ui,Segoe UI,Roboto,Arial;line-height:1.5">
            <h2>Your MediFlow account has been approved</h2>
            <p>Hello ${updated.username},</p>
            <p>Your signup request has been authorized. You can now sign in to MediFlow.</p>
          </div>
        `;
        try {
          await sendEmail({ to: [updated.email], subject: "MediFlow: Your account is approved", html });
        } catch (e) {
          console.error("Approval email failed", e);
        }
      }

      return json({ ok: true });
    }

    if (action === "create_user") {
      const { requesterId } = await requireAdmin("full");

      const providedEmail = normalizeEmail(payload.email);
      const providedUsernameRaw = typeof payload.username === "string" ? payload.username.trim() : "";
      const providedUsernameNorm = normalizeUsername(providedUsernameRaw);
      const facilityName = typeof payload.facilityName === "string" ? payload.facilityName.trim() : "";
      const role = payload.role as UserRole | undefined;
      const providerType = typeof payload.providerType === "string" ? payload.providerType : undefined;
      const lga = typeof payload.lga === "string" ? payload.lga : undefined;
      const state = typeof payload.state === "string" ? payload.state : undefined;
      const adminScope = payload.adminScope as AdminScope | undefined;

      if (!role) return json({ ok: false, error: "Missing role" }, 400);

      const isFieldProvider = role === "fieldProvider";
      if (!isFieldProvider && !providedEmail) return json({ ok: false, error: "Missing email" }, 400);

      if (isFieldProvider && !providedEmail && !providedUsernameNorm) {
        return json({ ok: false, error: "Provide at least a username or an email." }, 400);
      }

      if (providedUsernameNorm && !isValidUsername(providedUsernameNorm)) {
        return json({ ok: false, error: "Invalid username format. Use 3-24 chars: letters, numbers, underscore, dot." }, 400);
      }

      if (
        !([
          "fieldProvider",
          "supplier",
          "stateMalaria",
          "stateHIVTB",
          "nationalMalaria",
          "nationalHIVTB",
          "sfhTeam",
          "superAdmin",
        ] as string[]).includes(role)
      ) {
        return json({ ok: false, error: "Invalid role" }, 400);
      }

      if (adminScope && !(["none", "viewOnly", "full"] as string[]).includes(adminScope)) {
        return json({ ok: false, error: "Invalid adminScope" }, 400);
      }

      // Determine final public username (required in profile table).
      let finalUsername = providedUsernameNorm;
      if (!finalUsername) {
        // Email-only: derive from local-part.
        finalUsername = providedEmail.split("@")[0].toLowerCase();
        finalUsername = finalUsername.replace(/[^a-z0-9_.]/g, "_").slice(0, 24);
        if (finalUsername.length < 3) finalUsername = `user_${crypto.randomUUID().slice(0, 8)}`;
      }

      // Ensure username uniqueness (case-insensitive). Best-effort.
      // We still rely on the DB unique index to be the source of truth.
      for (let i = 0; i < 5; i++) {
        const { data: existingU } = await adminDb.from("users").select("id").ilike("username", finalUsername).maybeSingle();
        if (!existingU) break;
        finalUsername = `${finalUsername.slice(0, 18)}_${Math.floor(Math.random() * 9999)}`.slice(0, 24);
      }

      // For username-only accounts, Supabase auth still needs an email internally.
      // We create a synthetic, non-routable auth email.
      const syntheticUserId = crypto.randomUUID();
      const isSynthetic = !providedEmail;
      const authEmail = isSynthetic ? makeSyntheticAuthEmail(syntheticUserId) : providedEmail;
      const contactEmail = isSynthetic ? null : providedEmail;

      // Generate a strong one-time password.
      const password = generatePassword(14);

      // 1) Create auth user (Admin API)
      const { data: created, error: createErr } = await adminDb.auth.admin.createUser({
        email: authEmail,
        password,
        email_confirm: true,
        user_metadata: {
          username: finalUsername,
          role,
          facilityName: facilityName || undefined,
          providerType,
          lga,
          state,
        },
      });

      if (createErr || !created.user) {
        const msg = (createErr as any)?.message ?? "Failed to create auth user";
        return json({ ok: false, error: msg }, 400);
      }

      const userId = created.user.id;
      const effectiveScope: AdminScope = adminScope ?? (role === "superAdmin" ? "full" : "none");

      // 2) Upsert profile row (schema-flexible).
      const profRes = await upsertNewUserProfile({
        userId,
        username: finalUsername,
        authEmail,
        contactEmail,
        isSyntheticAuthEmail: isSynthetic,
        role,
        facilityName: facilityName || null,
        providerType: providerType ?? null,
        lga: lga ?? null,
        state: state ?? null,
        requesterId,
        adminScope: effectiveScope,
      });

      if ((profRes as any)?.error) {
        // Roll back auth user if profile creation fails.
        try {
          await adminDb.auth.admin.deleteUser(userId);
        } catch (_) {
          // ignore
        }

        const errMsg =
          (profRes as any)?.error?.message ||
          (profRes as any)?.error?.details ||
          (profRes as any)?.error?.hint ||
          "Profile upsert failed";

        // Return a debuggable error to the client.
        return json(
          {
            ok: false,
            error: "Profile upsert failed",
            code: "profile_upsert_failed",
            details: {
              message: errMsg,
              tableTried: (profRes as any)?.table ?? null,
            },
          },
          500,
        );
      }

      return json({ ok: true, userId, email: contactEmail ?? authEmail, authEmail, isSyntheticAuthEmail: isSynthetic, username: finalUsername, password });
    }

    if (action === "reset_password") {
      await requireAdmin("full");

      const userId = typeof payload.userId === "string" ? payload.userId.trim() : "";
      if (!userId) return json({ ok: false, error: "Missing userId" }, 400);

      const customPassword = typeof payload.customPassword === "string" ? payload.customPassword.trim() : "";

      // Use provided password (if any); otherwise generate a strong one.
      const password = customPassword ? customPassword : generatePassword(14);

      if (customPassword) {
        // Basic validation to prevent accidental weak resets.
        if (password.length < 8) return json({ ok: false, error: "Custom password must be at least 8 characters." }, 400);
        const hasLetter = /[A-Za-z]/.test(password);
        const hasNumber = /\d/.test(password);
        if (!hasLetter || !hasNumber) {
          return json({ ok: false, error: "Custom password must include at least one letter and one number." }, 400);
        }
      }

      // 1) Update auth password via Admin API
      const { data: updatedAuth, error: updAuthErr } = await adminDb.auth.admin.updateUserById(userId, {
        password,
      });

      if (updAuthErr) {
        console.error("Auth password reset failed", updAuthErr);
        return json({ ok: false, error: (updAuthErr as any)?.message ?? "Password reset failed" }, 400);
      }

      const email = (updatedAuth?.user?.email as string | null) ?? null;
      const now = new Date().toISOString();

      // 2) Best-effort: mark profile to force password change on next sign-in.
      // This is schema-flexible; if the column doesn't exist, we ignore.
      try {
        await resilientUpdate(
          adminDb,
          "users",
          { forcePasswordChange: true, force_password_change: true, updatedAt: now, updated_at: now } as any,
          { id: userId },
        );
      } catch (e) {
        console.error("Profile forcePasswordChange update failed (ignored)", e);
      }

      return json({ ok: true, userId, email, password });
    }

    return json({ ok: false, error: "Unknown action" }, 400);
  } catch (e) {
    if (e instanceof HttpError) {
      return json({ ok: false, error: e.message, code: e.code, details: e.details ?? null }, e.status);
    }
    return json({ ok: false, error: (e as Error).message ?? String(e), code: "internal_error" }, 500);
  }
});
