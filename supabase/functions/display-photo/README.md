Deploy after running migrations/20261025_display_devices.sql:

    supabase functions deploy display-photo --no-verify-jwt

This function intentionally accepts a random device secret in its POST body and
validates it through rr_display_photo_path. It does not accept a user-selected
storage path. The database checks paired ownership, admin membership, screen
schedule, photo permission, selected classes, and the organization/student path.
SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are supplied by
Supabase to deployed functions. Never place the service-role key in website files.
