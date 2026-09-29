CREATE TABLE invite_reward_dead_letters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invite_id uuid NOT NULL REFERENCES invites(id),
  inviter_id uuid NOT NULL,
  amount integer NOT NULL,
  error_message text NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz
);

ALTER TABLE invite_reward_dead_letters ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public._fulfil_invite_reward()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_invite  RECORD;
  v_days    INT;
  v_friends INT;
  v_amount  INT;
BEGIN
  FOR v_invite IN
    SELECT i.id, i.inviter_id, i.created_at
    FROM invites i
    WHERE i.accepted_by = NEW.user_id
      AND i.status = 'accepted'
    FOR UPDATE
  LOOP
    IF EXISTS (
      SELECT 1 FROM coin_transactions
      WHERE transaction_type = 'invite_reward'
        AND reference_id = v_invite.id::text
    ) THEN
      CONTINUE;
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM auth.users u
      WHERE u.id = NEW.user_id
        AND u.created_at > v_invite.created_at
    ) THEN
      CONTINUE;
    END IF;

    SELECT COUNT(DISTINCT check_in_date) INTO v_days
    FROM daily_team_checkins
    WHERE user_id = NEW.user_id;

    IF v_days < 2 THEN
      CONTINUE;
    END IF;

    SELECT COUNT(*) INTO v_friends
    FROM friendships
    WHERE status = 'accepted'
      AND (user_id = v_invite.inviter_id OR friend_id = v_invite.inviter_id);

    v_amount := CASE
      WHEN v_friends < 30 THEN 20
      WHEN v_friends < 60 THEN 10
      WHEN v_friends < 90 THEN 5
      ELSE 2
    END;

    BEGIN
      PERFORM award_coins(
        v_invite.inviter_id, v_amount, 'invite_reward',
        'Buddy invite paid off', v_invite.id::text
      );
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO invite_reward_dead_letters (invite_id, inviter_id, amount, error_message)
      VALUES (v_invite.id, v_invite.inviter_id, v_amount, SQLERRM);
    END;
  END LOOP;

  RETURN NULL;
END;
$function$;
