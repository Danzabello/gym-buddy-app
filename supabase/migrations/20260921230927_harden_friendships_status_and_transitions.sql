-- LIVE-15 close-out (friendships). The table had no CHECK on status, an INSERT
-- policy that only checked auth.uid() = user_id, and an UPDATE policy
-- (recipient only) with no WITH CHECK and no column limit. Verified in a
-- rolled-back transaction as the authenticated role: a client could INSERT
-- (me, victim, 'accepted') with no request and immediately read every one of
-- the victim's check-ins (the "check-ins for their teams and friends" SELECT
-- policy trusts accepted friendships), could insert 'garbage' or NULL
-- statuses, and a recipient could rewrite who sent a request.
--
-- The app only ever INSERTs 'pending' (sendFriendRequest) and only ever
-- UPDATEs pending -> accepted as the recipient (acceptFriendRequest); decline
-- and remove are DELETEs. create_invite_team (SECURITY DEFINER) inserts rows
-- born 'accepted' and is not affected: it bypasses RLS, and the trigger below
-- is UPDATE-only.
--
-- Live pre-check: 7 rows, all 'accepted', none NULL, no self-friends, no NULL
-- parties.
--
-- NULL-safety (found by testing the literal design on a temp table):
--  * CHECK (status IN (...)) passes on NULL, so status is also SET NOT NULL.
--  * "IF NOT (OLD.status = 'pending' AND NEW.status = 'accepted')" is NULL
--    (and so falls through) when NEW.status is NULL; "IS NOT TRUE" rejects it.
--  * NEW.user_id <> OLD.user_id is NULL when either side is NULL, which let
--    user_id be set to NULL past the "parties are immutable" rule;
--    IS DISTINCT FROM does not.
ALTER TABLE public.friendships ALTER COLUMN status SET NOT NULL;

ALTER TABLE public.friendships
  ADD CONSTRAINT friendships_status_check CHECK (status IN ('pending', 'accepted'));

DROP POLICY "Users can send friend requests" ON public.friendships;
CREATE POLICY "Users can send friend requests" ON public.friendships
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id AND status = 'pending' AND friend_id <> user_id);

CREATE OR REPLACE FUNCTION public._enforce_friendship_transition()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.user_id IS DISTINCT FROM OLD.user_id OR NEW.friend_id IS DISTINCT FROM OLD.friend_id THEN
    RAISE EXCEPTION 'friendship parties are immutable';
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF (OLD.status = 'pending' AND NEW.status = 'accepted') IS NOT TRUE THEN
      RAISE EXCEPTION 'invalid friendship status transition from % to %',
        OLD.status, NEW.status;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER enforce_friendship_transition
BEFORE UPDATE ON public.friendships
FOR EACH ROW
EXECUTE FUNCTION public._enforce_friendship_transition();
