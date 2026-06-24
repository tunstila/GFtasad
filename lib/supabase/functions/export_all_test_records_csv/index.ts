// Supabase Edge Function: export_all_test_records_csv
// - Generates a CSV export of all synced test_records
// - Enforces superAdmin authorization server-side (do not trust client claims)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-max-age": "86400",
};

type DbUser = {
  id: string;
  username?: string | null;
  email?: string | null;
  role?: string | null;
  admin_scope?: string | null;
  adminScope?: string | null;
  facility_name?: string | null;
  facilityName?: string | null;
  state?: string | null;
  lga?: string | null;
  ward?: string | null;
};

type DbBusinessAddress = {
  user_id: string;
  state?: string | null;
  lga?: string | null;
  ward?: string | null;
};

function jsonResponse(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...CORS_HEADERS,
      "content-type": "application/json; charset=utf-8",
    },
  });
}

function csvEscape(v: unknown): string {
  if (v === null || v === undefined) return "";
  const s = String(v);
  // Escape quotes by doubling them.
  const escaped = s.replace(/"/g, '""');
  // Quote if it contains comma, quote, or line break.
  if (/[",\n\r]/.test(escaped)) return `"${escaped}"`;
  return escaped;
}

function pick(obj: Record<string, unknown>, keys: string[]) {
  for (const k of keys) {
    const v = obj[k];
    if (v !== undefined && v !== null && String(v).trim() !== "") return v;
  }
  return null;
}

function normalizeList(v: unknown): string {
  if (v === null || v === undefined) return "";
  if (Array.isArray(v)) return v.map((e) => String(e)).filter((s) => s.trim().length > 0).join("; ");
  // Some legacy fields can be comma-separated.
  const s = String(v);
  return s;
}

function yesNo(v: unknown): string {
  if (v === true) return "Yes";
  if (v === false) return "No";
  const s = String(v ?? "").trim().toLowerCase();
  if (s === "true") return "Yes";
  if (s === "false") return "No";
  return String(v ?? "");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return jsonResponse(405, { error: "Method not allowed" });

  try {
    const authHeader = req.headers.get("authorization") ?? "";
    if (!authHeader.toLowerCase().startsWith("bearer ")) return jsonResponse(401, { error: "Missing Authorization header" });

    // 1) Verify the JWT using ANON key (no service role here).
    const userClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData?.user) return jsonResponse(401, { error: "Invalid session" });

    const requesterId = userData.user.id;

    // 2) Use service role for reads (bypass RLS), but still enforce our own authorization.
    const adminClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    // NOTE: We intentionally use `select('*')` here.
    // Different deployments have different column names (snake_case vs camelCase), and selecting
    // a non-existent column causes PostgREST to error. `*` is schema-safe.
    const { data: requesterProfile, error: profErr } = await adminClient
      .from("users")
      .select("*")
      .eq("id", requesterId)
      .maybeSingle<DbUser>();

    if (profErr) {
      return jsonResponse(500, {
        error: "Failed to load requester profile",
        details: profErr.message,
      });
    }

    const role = (requesterProfile?.role ?? "").toString();
    const adminScope = (requesterProfile?.admin_scope ?? requesterProfile?.adminScope ?? "").toString();
    const isSuperAdmin = role == "superAdmin" || adminScope == "full";

    if (!isSuperAdmin) {
      // Do not leak data.
      return jsonResponse(403, { error: "Forbidden" });
    }

    // 3) Fetch ALL test records in pages. This exports synced records only (Supabase rows).
    // NOTE: If your table is extremely large, consider date filters or async export.
    const pageSize = 1000;
    let from = 0;
    const rows: Record<string, unknown>[] = [];

    while (true) {
      const { data, error } = await adminClient
        .from("test_records")
        .select("*")
        .range(from, from + pageSize - 1);

      if (error) return jsonResponse(500, { error: `Failed to read test_records: ${error.message}` });
      const batch = (data ?? []) as Record<string, unknown>[];
      if (batch.length === 0) break;
      rows.push(...batch);
      if (batch.length < pageSize) break;
      from += pageSize;
    }

    // 3b) Fetch ALL prevention messaging records in pages.
    let pmFrom = 0;
    const pmRowsAll: Record<string, unknown>[] = [];
    while (true) {
      const { data, error } = await adminClient
        .from("prevention_messaging_records")
        .select("*")
        .range(pmFrom, pmFrom + pageSize - 1);
      if (error) {
        // Schema-tolerant: some deployments may not have this table.
        break;
      }
      const batch = (data ?? []) as Record<string, unknown>[];
      if (batch.length === 0) break;
      pmRowsAll.push(...batch);
      if (batch.length < pageSize) break;
      pmFrom += pageSize;
    }

    // 4) Fetch FieldProvider profiles for better context.
    const providerIds = Array.from(
      new Set(
        rows
          .map((r) => pick(r, ["userid", "user_id", "userId", "created_by", "createdBy", "provider_id", "providerId"]))
          .filter((v) => v !== null)
          .map((v) => String(v)),
      ),
    );

    const providerIdsAll = [...providerIds];
    for (const r of pmRowsAll) {
      const uid = pick(r, ["userid", "user_id", "userId", "created_by", "createdBy", "provider_id", "providerId"]);
      if (uid) providerIdsAll.push(String(uid));
    }

    const providerIdsUniq = Array.from(new Set(providerIdsAll));

    const providerById = new Map<string, DbUser>();
    if (providerIdsUniq.length > 0) {
      const { data: providers, error: provErr } = await adminClient
        .from("users")
        // Same reason as above: schema-safe across deployments.
        .select("*")
        .in("id", providerIdsUniq);

      if (!provErr && Array.isArray(providers)) {
        for (const p of providers as DbUser[]) providerById.set(p.id, p);
      }
    }

    // 4b) Fetch provider business locations (state/LGA/ward) from the source-of-truth table.
    // This is where the FieldProvider "Business" profile tab persists location.
    const providerBizById = new Map<string, DbBusinessAddress>();
    if (providerIdsUniq.length > 0) {
      try {
        const { data: bizRows, error: bizErr } = await adminClient
          .from("user_business_addresses")
          .select("user_id,state,lga,ward")
          .in("user_id", providerIdsUniq);

        if (!bizErr && Array.isArray(bizRows)) {
          for (const b of bizRows as DbBusinessAddress[]) providerBizById.set(String(b.user_id), b);
        }
      } catch (_) {
        // Schema-tolerant: older deployments may not have the table.
      }
    }

    // 5) Build stable CSV with readable common columns + program-specific columns + raw JSON.
    const headers = [
      "record_id",
      "record_source",
      "created_at",
      "updated_at",
      "synced_at",
      "fieldprovider_id",
      "fieldprovider_username",
      "fieldprovider_facility_name",
      "state",
      "lga",
      "ward",
      "client_name",
      "client_code",
      "program",
      "test_date",
      "sex",
      "pregnant",
      "visit_type",
      "age",
      "age_band",
      "date_of_birth",
      "phone_number",

      // Malaria (expanded + legacy)
      "client_address",
      "client_groups",
      "first_time_visit",
      "referred_from",
      "other_referral_source",
      "symptoms_presented",
      "other_symptoms_presented",
      "mrdt_result",
      "mrdt_tested",
      "mrdt_positive",
      "fever_presented",
      "act_given",
      "act_given_option",
      "other_act_given",
      "referral_for_danger_signs",
      "danger_signs_referral_facility",

      // HIV
      "hiv_counselling",
      "hivst_type",
      "determine_test",
      "hiv_test_result",
      "art_linkage",
      "referral_facility",
      "hiv_previous_testing",
      "hts_type",
      "hivst_kit_type",
      "hivst_service_delivery_model",
      "tb_symptoms_presented",
      "referral_services",
      "other_referral_service",
      "prep_assessed",
      "prep_eligible",
      "prep_offered",
      "prep_accepted",
      "prep_started",
      "prep_continued",
      "prep_ref_source",

      // TB
      "tb_screening",

      "notes",

      // Prevention messaging specific
      "pm_first_time_visit",
      "pm_referred_from",
      "pm_other_referred_from",
      "pm_educated_on_hiv_prevention",
      "pm_educated_on_hiv_testing",
      "pm_educated_on_malaria_prevention",
      "pm_referral_services",
      "pm_other_referral_service",
      "pm_referral_facility",

      // Full raw row for completeness across schema variants
      "form_details_json",
    ];

    const lines: string[] = [];
    lines.push(headers.join(","));

    const allRows: Array<{ source: string; row: Record<string, unknown> }> = [];
    for (const r of rows) allRows.push({ source: "test_records", row: r });
    for (const r of pmRowsAll) allRows.push({ source: "prevention_messaging_records", row: r });

    for (const item of allRows) {
      const r = item.row;
      const fieldProviderId = String(pick(r, ["userid", "user_id", "userId", "created_by", "createdBy", "provider_id", "providerId"]) ?? "");
      const p = providerById.get(fieldProviderId);
      const biz = providerBizById.get(fieldProviderId);

      const programRaw = item.source === "prevention_messaging_records"
        ? "prevention_messaging"
        : (pick(r, ["program", "intervention_area", "interventionArea", "health_program", "healthProgram"]) ?? "");

      const row: Record<string, unknown> = {
        record_id: pick(r, ["id", "ID"]) ?? "",
        record_source: item.source,
        created_at: pick(r, ["created_at", "createdAt", "created", "inserted_at"]) ?? "",
        updated_at: pick(r, ["updated_at", "updatedAt", "updated"]) ?? "",
        synced_at: pick(r, ["synced_at", "syncedAt", "last_synced_at"]) ?? "",

        fieldprovider_id: fieldProviderId,
        fieldprovider_username: (p?.username ?? "").toString(),
        fieldprovider_facility_name: String(p?.facility_name ?? p?.facilityName ?? ""),

        // Prefer business profile location (source of truth), else fall back to `users`.
        state: String(biz?.state ?? p?.state ?? ""),
        lga: String(biz?.lga ?? p?.lga ?? ""),
        ward: String(biz?.ward ?? p?.ward ?? ""),

        client_name: pick(r, ["clientname", "client_name", "clientName"]) ?? "",
        client_code: pick(r, ["clientid", "client_id", "clientId", "client_code", "clientCode"]) ?? "",
        program: String(programRaw),
        test_date: item.source === "prevention_messaging_records" ? (pick(r, ["createdat", "created_at", "createdAt"]) ?? "") : (pick(r, ["test_date", "testDate", "testdate"]) ?? ""),
        sex: pick(r, ["sex"]) ?? "",
        pregnant: yesNo(pick(r, ["pregnant"])) ,
        visit_type: pick(r, ["visit_type", "visitType", "visittype"]) ?? "",
        age: pick(r, ["age"]) ?? "",
        age_band: pick(r, ["ageband", "age_band", "ageBand"]) ?? "",
        date_of_birth: pick(r, ["dateofbirth", "date_of_birth", "dateOfBirth", "dob"]) ?? "",
        phone_number: pick(r, ["phone_number", "phoneNumber", "phonenumber", "phone"]) ?? "",

        client_address: pick(r, ["client_address", "clientAddress", "clientaddress"]) ?? "",
        client_groups: normalizeList(pick(r, ["client_groups", "clientGroups", "clientgroups"])) ,
        first_time_visit: yesNo(pick(r, ["first_time_visit", "firstTimeVisit", "firsttimevisit"])) ,
        referred_from: pick(r, ["referred_from", "referredFrom", "referredfrom"]) ?? "",
        other_referral_source: pick(r, ["other_referral_source", "otherReferralSource", "otherreferralsource"]) ?? "",
        symptoms_presented: normalizeList(pick(r, ["symptoms_presented", "symptomsPresented", "symptomspresented"])) ,
        other_symptoms_presented: pick(r, ["other_symptoms_presented", "otherSymptomsPresented", "othersymptomspresented"]) ?? "",
        mrdt_result: pick(r, ["mrdt_result", "mRDTResult", "mrdtResult"]) ?? "",
        mrdt_tested: yesNo(pick(r, ["mrdttested", "mRDTTested", "mrdt_tested"])) ,
        mrdt_positive: yesNo(pick(r, ["mrdtpositive", "mRDTPositive", "mrdt_positive"])) ,
        fever_presented: yesNo(pick(r, ["feverpresented", "feverPresented", "fever_presented"])) ,
        act_given: yesNo(pick(r, ["actgiven", "actGiven", "act_given"])) ,
        act_given_option: pick(r, ["act_given_option", "actGivenOption", "actgivenoption"]) ?? "",
        other_act_given: pick(r, ["other_act_given", "otherActGiven", "otheractgiven"]) ?? "",
        referral_for_danger_signs: yesNo(pick(r, ["referral_for_danger_signs", "referralForDangerSigns", "referralfordangersigns"])) ,
        danger_signs_referral_facility: pick(r, ["danger_signs_referral_facility", "dangerSignsReferralFacility", "dangersignsreferralfacility"]) ?? "",

        hiv_counselling: yesNo(pick(r, ["hivcounselling", "hivCounselling", "hiv_counselling"])) ,
        hivst_type: pick(r, ["hivsttype", "hivstType", "hivst_type"]) ?? "",
        determine_test: pick(r, ["determinetest", "determineTest", "determine_test"]) ?? "",
        hiv_test_result: pick(r, ["hiv_test_result", "hivTestResult", "hivtestresult"]) ?? "",
        art_linkage: pick(r, ["artlinkage", "artLinkage", "art_linkage"]) ?? "",
        referral_facility: pick(r, ["referralfacility", "referralFacility", "referral_facility"]) ?? "",
        hiv_previous_testing: pick(r, ["hiv_previous_testing", "hivPreviousTesting", "hivprevioustesting"]) ?? "",
        hts_type: pick(r, ["hts_type", "htsType", "htstype"]) ?? "",
        hivst_kit_type: pick(r, ["hivst_kit_type", "hivstKitType", "hivstkittype"]) ?? "",
        hivst_service_delivery_model: pick(r, ["hivst_service_delivery_model", "hivstServiceDeliveryModel"]) ?? "",
        tb_symptoms_presented: normalizeList(pick(r, ["tb_symptoms_presented", "tbSymptomsPresented"])) ,
        referral_services: normalizeList(pick(r, ["referral_services", "referralServices"])) ,
        other_referral_service: pick(r, ["other_referral_service", "otherReferralService"]) ?? "",
        prep_assessed: yesNo(pick(r, ["prepassessed", "prepAssessed", "prep_assessed"])) ,
        prep_eligible: yesNo(pick(r, ["prepeligible", "prepEligible", "prep_eligible"])) ,
        prep_offered: yesNo(pick(r, ["prepoffered", "prepOffered", "prep_offered"])) ,
        prep_accepted: yesNo(pick(r, ["prepaccepted", "prepAccepted", "prep_accepted"])) ,
        prep_started: yesNo(pick(r, ["prepstarted", "prepStarted", "prep_started"])) ,
        prep_continued: yesNo(pick(r, ["prepcontinued", "prepContinued", "prep_continued"])) ,
        prep_ref_source: pick(r, ["preprefsource", "prepRefSource", "prep_ref_source"]) ?? "",

        tb_screening: yesNo(pick(r, ["tb_screening", "tbScreening"])) ,
        notes: pick(r, ["notes"]) ?? "",

        pm_first_time_visit: yesNo(pick(r, ["firsttimevisit", "first_time_visit", "firstTimeVisit"])) ,
        pm_referred_from: pick(r, ["referredfrom", "referred_from", "referredFrom"]) ?? "",
        pm_other_referred_from: pick(r, ["otherreferredfrom", "other_referred_from", "otherReferredFrom"]) ?? "",
        pm_educated_on_hiv_prevention: yesNo(pick(r, ["educatedonhivprevention", "educated_on_hiv_prevention", "educatedOnHivPrevention"])) ,
        pm_educated_on_hiv_testing: yesNo(pick(r, ["educatedonhivtestingoptions", "educated_on_hiv_testing_options", "educatedOnHivTestingOptions"])) ,
        pm_educated_on_malaria_prevention: yesNo(pick(r, ["educatedonmalariaprevention", "educated_on_malaria_prevention", "educatedOnMalariaPrevention", "educatedonmalariapreventiontreatment", "educated_on_malaria_prevention_treatment"])) ,
        pm_referral_services: normalizeList(pick(r, ["referralservices", "referral_services", "referralServices"])) ,
        pm_other_referral_service: pick(r, ["otherreferralservice", "other_referral_service", "otherReferralService"]) ?? "",
        pm_referral_facility: pick(r, ["referralfacility", "referral_facility", "referralFacility"]) ?? "",
        form_details_json: JSON.stringify(r),
      };

      const line = headers.map((h) => csvEscape((row as Record<string, unknown>)[h])).join(",");
      lines.push(line);
    }

    const csv = lines.join("\n");
    const now = new Date();
    const yyyy = now.getFullYear();
    const mm = String(now.getMonth() + 1).padStart(2, "0");
    const dd = String(now.getDate()).padStart(2, "0");
    const filename = `all_test_records_${yyyy}-${mm}-${dd}.csv`;

    return jsonResponse(200, { filename, csv, rowCount: allRows.length });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return jsonResponse(500, { error: msg });
  }
});
