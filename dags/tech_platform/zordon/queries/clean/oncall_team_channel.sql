SELECT
  id,
  opsgenie_schedule_id AS id_opsgenie_schedule,
  opsgenie_team,
  gchat_space,
  previous_day AS is_previous_day
FROM
  datalake_zordon_raw.oncall_team_channel
