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

function normalizeIdentifier(raw: unknown) {
  const v = typeof raw === "string" ? raw.trim() : "";
  return v;
}

function normalizeUsername(raw: string) {
  return raw.trim().toLowerCase();
}

function looksLikeEmail(v: string) {
  return v.includes("@");
}

// IMPORTANT: Do not leak whether a username exists.
function genericAuthFailure() {
  return json({ ok: false, error: "Invalid credentials." }, 401);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const payload = await req.json().catch(() => ({}));
    const identifier = normalizeIdentifier(payload.identifier);
    const password = typeof payload.password === "string" ? payload.password : "";

    if (!identifier || !password) return genericAuthFailure();

    // Use service role ONLY to resolve username -> auth email.
    const adminDb = createClient(url, serviceRoleKey);

    let emailToUse = "";
    if (looksLikeEmail(identifier)) {
      emailToUse = identifier.trim().toLowerCase();
    } else {
      const usernameNorm = normalizeUsername(identifier);
      const { data, error } = await adminDb
        .from("users")
        .select("email")
        .filter("username", "ilike", usernameNorm)
        .maybeSingle();

      if (error || !data?.email) {
        // Do not leak existence.
        return genericAuthFailure();
      }
      emailToUse = String(data.email).trim().toLowerCase();
    }

    // Perform actual password auth using anon key (normal auth path).
    const anonDb = createClient(url, anonKey);
    const { data: auth, error: authErr } = await anonDb.auth.signInWithPassword({ email: emailToUse, password });
    if (authErr || !auth.session) return genericAuthFailure();

    // Return tokens so the Flutter client can set the session.
    return json({
      ok: true,
      session: {
        access_token: auth.session.access_token,
        refresh_token: auth.session.refresh_token,
        token_type: auth.session.token_type,
        expires_in: auth.session.expires_in,
        expires_at: auth.session.expires_at,
        user: auth.user,
      },
    });
  } catch (_e) {
    // Always return the same failure to avoid account enumeration.
    return genericAuthFailure();
  }
});
