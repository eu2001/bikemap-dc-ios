// supabase/functions/delete-account/index.ts
//
// Edge function: deletes the calling user's account.
//
// Behavior (Apple App Store Guideline 5.1.1(v) compliant):
//   • Authenticates the caller via the JWT in the Authorization header.
//   • Deletes the user's bikes + their photos from Storage (private data).
//   • Deletes the user's push tokens.
//   • Anonymizes the user's POIs (community safety contributions are
//     preserved with author_id = NULL and author_username = "[Usuário excluído]").
//   • Deletes the user's profile row.
//   • Deletes the auth.users record (terminates the account).
//
// Requirements:
//   • SUPABASE_SERVICE_ROLE_KEY must be set as a secret on the function
//     (Project Settings → Edge Functions → Secrets, or `supabase secrets set`).
//   • SUPABASE_URL is provided automatically by the Edge runtime.
//
// Deploy:
//   supabase functions deploy delete-account --no-verify-jwt
//   (--no-verify-jwt is required because we verify the JWT manually
//   so we can return clean error messages to the iOS client.)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
      return json({ error: "Server misconfigured" }, 500);
    }

    // ── 1. Authenticate the caller via their JWT ──────────────────
    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (!jwt) return json({ error: "Missing Authorization header" }, 401);

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
    if (userErr || !userData?.user) {
      return json({ error: "Invalid or expired token" }, 401);
    }
    const userId = userData.user.id;

    // ── 2. Collect bike photo paths for storage cleanup ───────────
    const { data: bikes, error: bikesFetchErr } = await admin
      .from("bikes")
      .select("image_url")
      .eq("user_id", userId);
    if (bikesFetchErr) throw bikesFetchErr;

    const bikePhotoPaths = (bikes ?? [])
      .map((b: { image_url: string | null }) => extractStoragePath(b.image_url, "bike-photos"))
      .filter((p): p is string => p !== null);

    // ── 3. Delete bike photos from Storage ────────────────────────
    if (bikePhotoPaths.length > 0) {
      const { error: rmErr } = await admin.storage
        .from("bike-photos")
        .remove(bikePhotoPaths);
      if (rmErr) console.warn("bike-photos remove warning:", rmErr.message);
    }

    // ── 4. Delete bikes ───────────────────────────────────────────
    const { error: bikesDelErr } = await admin
      .from("bikes")
      .delete()
      .eq("user_id", userId);
    if (bikesDelErr) throw bikesDelErr;

    // ── 5. Delete push tokens ─────────────────────────────────────
    const { error: tokensDelErr } = await admin
      .from("push_tokens")
      .delete()
      .eq("user_id", userId);
    if (tokensDelErr) console.warn("push_tokens delete warning:", tokensDelErr.message);

    // ── 6. Anonymize POIs (preserve community map data) ───────────
    // Apple's guideline requires deleting the *account*, not community
    // safety contributions — those are kept with no link to the user.
    const { error: poisErr } = await admin
      .from("pois")
      .update({
        author_id: null,
        author_username: "[Usuário excluído]",
      })
      .eq("author_id", userId);
    if (poisErr) console.warn("pois anonymize warning:", poisErr.message);

    // ── 7. Delete profile row ─────────────────────────────────────
    const { error: profileErr } = await admin
      .from("profiles")
      .delete()
      .eq("id", userId);
    if (profileErr) console.warn("profile delete warning:", profileErr.message);

    // ── 8. Delete auth user (this is the actual "account deletion") ──
    const { error: authErr } = await admin.auth.admin.deleteUser(userId);
    if (authErr) throw authErr;

    return json({ ok: true });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("delete-account error:", message);
    return json({ error: message }, 500);
  }
});

// ── Helpers ────────────────────────────────────────────────────────

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

/**
 * Extract the storage object path from a public URL.
 * Example input:
 *   https://xxx.supabase.co/storage/v1/object/public/bike-photos/bike_1730000000.jpg
 * Returns: "bike_1730000000.jpg"
 */
function extractStoragePath(url: string | null, bucket: string): string | null {
  if (!url) return null;
  const marker = `/storage/v1/object/public/${bucket}/`;
  const idx = url.indexOf(marker);
  if (idx === -1) return null;
  return url.substring(idx + marker.length);
}
