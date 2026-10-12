-- 05b: the 4 leftover test teams deleted by 20261013010000_credit_sweep_05b (parents first). Captured 2026-10-12T23:18:17Z.
-- buddy_teams: 4 rows
INSERT INTO public.buddy_teams SELECT * FROM jsonb_populate_recordset(null::public.buddy_teams, $j$[
  {
    "created_at": "2026-07-01T23:18:34.178186+00:00",
    "created_by": null,
    "id": "05c20a6a-e239-47e2-93c0-347e6324e927",
    "is_coach_max_team": false,
    "max_members": 2,
    "team_emoji": "💪",
    "team_name": "rokitest & newtestaccount2",
    "updated_at": "2026-07-01T23:18:34.178186+00:00"
  },
  {
    "created_at": "2025-12-18T09:58:23.113452+00:00",
    "created_by": "2b61ae0f-655f-4111-b754-b18e00afe9d8",
    "id": "3847194a-24c5-48c4-a7b7-1858011bc730",
    "is_coach_max_team": false,
    "max_members": 2,
    "team_emoji": "💪",
    "team_name": "newtestaccount3 & rokitest",
    "updated_at": "2025-12-18T09:58:23.113452+00:00"
  },
  {
    "created_at": "2026-03-14T15:01:03.516305+00:00",
    "created_by": "5e5c9752-7ff9-4b67-8800-915c2515d88b",
    "id": "a3ae42dc-8fb4-4c70-b4b5-2bcf5120f080",
    "is_coach_max_team": false,
    "max_members": 2,
    "team_emoji": "💪",
    "team_name": "sophtest & rokitest",
    "updated_at": "2026-03-14T15:01:03.516305+00:00"
  },
  {
    "created_at": "2026-03-15T20:52:21.087872+00:00",
    "created_by": null,
    "id": "c06f57ea-0868-46b8-8887-489a008efe78",
    "is_coach_max_team": false,
    "max_members": 2,
    "team_emoji": "💪",
    "team_name": "rokitest & testtest6",
    "updated_at": "2026-03-15T20:52:21.087872+00:00"
  }
]$j$::jsonb);
-- team_members: 4 rows
INSERT INTO public.team_members SELECT * FROM jsonb_populate_recordset(null::public.team_members, $j$[
  {
    "created_at": "2025-12-18T09:58:23.671918+00:00",
    "id": "1ec1b1c1-305e-4c1e-8492-a789ec7801ec",
    "is_favorite": false,
    "joined_at": "2025-12-18T09:58:23.671918+00:00",
    "role": "member",
    "team_id": "3847194a-24c5-48c4-a7b7-1858011bc730",
    "user_id": "2b61ae0f-655f-4111-b754-b18e00afe9d8"
  },
  {
    "created_at": "2026-03-15T20:52:21.698301+00:00",
    "id": "c225e295-241a-454b-a45e-41e2f3f8a35d",
    "is_favorite": false,
    "joined_at": "2026-03-15T20:52:21.698301+00:00",
    "role": "member",
    "team_id": "c06f57ea-0868-46b8-8887-489a008efe78",
    "user_id": "64de5abb-df2e-4d87-b80a-4dc70742df86"
  },
  {
    "created_at": "2026-07-01T23:18:35.036209+00:00",
    "id": "c54b80f7-9716-402b-93ae-2eb13ee9bdd4",
    "is_favorite": false,
    "joined_at": "2026-07-01T23:18:35.036209+00:00",
    "role": "member",
    "team_id": "05c20a6a-e239-47e2-93c0-347e6324e927",
    "user_id": "07960b8c-300b-44cb-89dd-93f3f38099b8"
  },
  {
    "created_at": "2026-03-14T15:01:04.171655+00:00",
    "id": "ea36db81-bb20-42e3-ae13-e2e8016b7c9d",
    "is_favorite": false,
    "joined_at": "2026-03-14T15:01:04.171655+00:00",
    "role": "member",
    "team_id": "a3ae42dc-8fb4-4c70-b4b5-2bcf5120f080",
    "user_id": "5e5c9752-7ff9-4b67-8800-915c2515d88b"
  }
]$j$::jsonb);
-- team_streaks: 4 rows
INSERT INTO public.team_streaks SELECT * FROM jsonb_populate_recordset(null::public.team_streaks, $j$[
  {
    "best_streak": 1,
    "created_at": "2025-12-18T09:58:23.727689+00:00",
    "current_streak": 0,
    "end_date": null,
    "end_reason": null,
    "id": "06f0d4df-dbbf-4e69-a2e6-26e01feea4d6",
    "is_active": true,
    "is_favorite": false,
    "last_interaction_at": "2026-07-02T17:48:09.253429+00:00",
    "last_workout_date": "2026-07-02",
    "longest_streak": 1,
    "start_date": "2025-12-18",
    "team_id": "3847194a-24c5-48c4-a7b7-1858011bc730",
    "total_workouts": 2,
    "updated_at": "2026-07-03T23:05:00.305617+00:00"
  },
  {
    "best_streak": 0,
    "created_at": "2026-03-15T20:52:21.816059+00:00",
    "current_streak": 0,
    "end_date": null,
    "end_reason": null,
    "id": "37db831b-1077-449c-88ce-af610b92df9d",
    "is_active": true,
    "is_favorite": false,
    "last_interaction_at": null,
    "last_workout_date": null,
    "longest_streak": 0,
    "start_date": "2026-03-15",
    "team_id": "c06f57ea-0868-46b8-8887-489a008efe78",
    "total_workouts": 0,
    "updated_at": "2026-03-15T20:52:21.816059+00:00"
  },
  {
    "best_streak": 0,
    "created_at": "2026-03-14T15:01:04.250518+00:00",
    "current_streak": 0,
    "end_date": null,
    "end_reason": null,
    "id": "4b10b319-59da-4eaa-aa97-4bed4c47d39a",
    "is_active": true,
    "is_favorite": true,
    "last_interaction_at": null,
    "last_workout_date": null,
    "longest_streak": 0,
    "start_date": "2026-03-14",
    "team_id": "a3ae42dc-8fb4-4c70-b4b5-2bcf5120f080",
    "total_workouts": 0,
    "updated_at": "2026-03-14T15:01:11.59609+00:00"
  },
  {
    "best_streak": 2,
    "created_at": "2026-07-01T23:18:35.177366+00:00",
    "current_streak": 0,
    "end_date": null,
    "end_reason": null,
    "id": "6236d716-9198-4acd-9e62-123b4b8fcaa7",
    "is_active": true,
    "is_favorite": false,
    "last_interaction_at": "2026-10-02T19:43:49.297346+00:00",
    "last_workout_date": "2026-10-02",
    "longest_streak": 2,
    "start_date": "2026-07-01",
    "team_id": "05c20a6a-e239-47e2-93c0-347e6324e927",
    "total_workouts": 4,
    "updated_at": "2026-10-03T23:05:00.458307+00:00"
  }
]$j$::jsonb);
-- daily_team_checkins: 7 rows
INSERT INTO public.daily_team_checkins SELECT * FROM jsonb_populate_recordset(null::public.daily_team_checkins, $j$[
  {
    "check_in_date": "2026-10-02",
    "check_in_time": "2026-10-02T19:43:49.297346+00:00",
    "created_at": "2026-10-02T19:43:49.297346+00:00",
    "id": "107a8108-3ab3-45f2-a0b3-feadf89e26a0",
    "team_streak_id": "6236d716-9198-4acd-9e62-123b4b8fcaa7",
    "user_id": "07960b8c-300b-44cb-89dd-93f3f38099b8"
  },
  {
    "check_in_date": "2026-07-02",
    "check_in_time": "2026-07-02T17:19:14.13689+00:00",
    "created_at": "2026-07-02T17:19:13.646731+00:00",
    "id": "1d9fc687-1bbb-4c79-acc1-2c49f655d309",
    "team_streak_id": "06f0d4df-dbbf-4e69-a2e6-26e01feea4d6",
    "user_id": "2b61ae0f-655f-4111-b754-b18e00afe9d8"
  },
  {
    "check_in_date": "2026-09-23",
    "check_in_time": "2026-09-22T23:00:07.482461+00:00",
    "created_at": "2026-09-22T23:00:07.490043+00:00",
    "id": "288df207-0c6c-41fb-9b60-f0edc42da3fe",
    "team_streak_id": "6236d716-9198-4acd-9e62-123b4b8fcaa7",
    "user_id": "07960b8c-300b-44cb-89dd-93f3f38099b8"
  },
  {
    "check_in_date": "2026-06-27",
    "check_in_time": "2026-06-27T15:42:12.851308+00:00",
    "created_at": "2026-06-27T15:42:12.872944+00:00",
    "id": "9a8cbb50-5e4a-48c4-87f6-4023d5e9be74",
    "team_streak_id": "06f0d4df-dbbf-4e69-a2e6-26e01feea4d6",
    "user_id": "2b61ae0f-655f-4111-b754-b18e00afe9d8"
  },
  {
    "check_in_date": "2026-10-01",
    "check_in_time": "2026-10-01T16:03:57.95256+00:00",
    "created_at": "2026-10-01T16:03:57.95256+00:00",
    "id": "a076b834-11dd-4021-bc2b-3ad11ea3d84a",
    "team_streak_id": "6236d716-9198-4acd-9e62-123b4b8fcaa7",
    "user_id": "07960b8c-300b-44cb-89dd-93f3f38099b8"
  },
  {
    "check_in_date": "2026-07-02",
    "check_in_time": "2026-07-02T16:55:34.86209+00:00",
    "created_at": "2026-07-02T16:55:34.378959+00:00",
    "id": "bec64291-904c-4415-8799-00a354946a43",
    "team_streak_id": "6236d716-9198-4acd-9e62-123b4b8fcaa7",
    "user_id": "07960b8c-300b-44cb-89dd-93f3f38099b8"
  },
  {
    "check_in_date": "2026-03-24",
    "check_in_time": "2026-03-24T00:13:46.487689+00:00",
    "created_at": "2026-03-24T00:13:45.209892+00:00",
    "id": "d283ff07-0898-4f4c-a859-bb21b058aa54",
    "team_streak_id": "06f0d4df-dbbf-4e69-a2e6-26e01feea4d6",
    "user_id": "2b61ae0f-655f-4111-b754-b18e00afe9d8"
  }
]$j$::jsonb);
-- streak_events: 1 rows
INSERT INTO public.streak_events SELECT * FROM jsonb_populate_recordset(null::public.streak_events, $j$[
  {
    "created_at": "2026-10-03T23:05:00.458307+00:00",
    "id": "24f2137f-ef8b-481b-9390-94dc430c2ab1",
    "kind": "own",
    "lost_streak": 2,
    "missed_user_id": null,
    "seen_at": null,
    "team_id": "05c20a6a-e239-47e2-93c0-347e6324e927",
    "user_id": "07960b8c-300b-44cb-89dd-93f3f38099b8"
  }
]$j$::jsonb);
