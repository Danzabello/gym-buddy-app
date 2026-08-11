-- Drop two redundant RLS policies on friendships.
--
-- The table carries duplicate pairs that are byte-identical in effect:
--
--   INSERT  "Users can create friend requests"          WITH CHECK (auth.uid() = user_id)
--           "Users can send friend requests"            WITH CHECK (auth.uid() = user_id)
--
--   UPDATE  "Recipients can accept friend requests"     USING (auth.uid() = friend_id)
--           "Users can update friendships they're part of"
--                                                       USING (auth.uid() = friend_id)
--
-- Permissive policies OR together, so a duplicate of an identical expression
-- grants nothing extra -- this is pure noise removal, not a permission change.
-- Effective access after this migration is unchanged: INSERT still requires
-- you to be the sender, UPDATE still requires you to be the recipient.
--
-- Which one goes, in each pair:
--
--  * INSERT: keep "Users can send friend requests" -- it names the action.
--    "create ... requests" describes the row rather than the intent.
--
--  * UPDATE: keep "Recipients can accept friend requests", which accurately
--    describes auth.uid() = friend_id. The other name is actively wrong:
--    "friendships they're part of" implies (user_id OR friend_id), but the
--    qual only ever matched the recipient. A future reader trusting that name
--    would believe senders can update their own rows, which they cannot.

DROP POLICY IF EXISTS "Users can create friend requests" ON public.friendships;
DROP POLICY IF EXISTS "Users can update friendships they're part of" ON public.friendships;
