# Supabase Edge Functions

This folder is version-controlled alongside the iOS app source so the backend
logic and the client code stay in sync.

## delete-account

Deletes the calling user's account (Apple App Store Guideline 5.1.1(v)).

### Deploy

```bash
# Install the Supabase CLI once (Homebrew on Mac)
brew install supabase/tap/supabase

# Log in and link to your project (one-time, from the repo root)
supabase login
supabase link --project-ref rwhwngayniazpruukblm

# Deploy
supabase functions deploy delete-account --no-verify-jwt

# Note: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are auto-injected by
# the Supabase Edge runtime — DO NOT try to set them with `supabase secrets set`
# (the CLI rejects any env var starting with SUPABASE_).
```

The `--no-verify-jwt` flag is required because the function verifies the
caller's JWT manually using the service-role admin client (so it can return
clean error messages to the iOS app).

### Verify it works

From any signed-in iOS session you can verify the function is reachable:

```bash
curl -X POST \
  "https://rwhwngayniazpruukblm.supabase.co/functions/v1/delete-account" \
  -H "Authorization: Bearer <user_jwt>" \
  -H "apikey: <anon_key>"
```

Successful response: `{"ok": true}`.

⚠️  **This actually deletes the user.** Test with a throwaway account first.

### What it does (in order)

1. Verifies the caller's JWT (returns 401 if invalid).
2. Deletes the user's bike photos from the `bike-photos` Storage bucket.
3. Deletes their `bikes` rows.
4. Deletes their `push_tokens` rows (non-fatal if missing).
5. Anonymizes their `pois` rows: `author_id → NULL`,
   `author_username → "[Usuário excluído]"`. Community map data
   is preserved.
6. Deletes their `profiles` row (non-fatal if missing).
7. Deletes the `auth.users` record (terminates the account).

### Why anonymize POIs instead of deleting?

Apple's guideline requires deletion of the **account**, not the user's
community contributions. Bike-theft reports, repair shops, paraciclos,
and other map data have public-safety value and are preserved with no
link back to the user — the same approach used by Reddit, StackOverflow,
and most community apps.

This is documented in section 4.1 of the app's privacy policy
(`/docs/privacy.html`).
