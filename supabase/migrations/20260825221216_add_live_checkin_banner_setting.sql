-- Adds a per-user toggle for the dashboard's live check-in banner (Part C
-- of the realtime check-in feature). Defaults true so existing users keep
-- seeing it until they opt out; the underlying ring animation is never
-- gated by this — only the banner is.
ALTER TABLE public.notification_settings
  ADD COLUMN IF NOT EXISTS live_checkin_banner boolean NOT NULL DEFAULT true;
