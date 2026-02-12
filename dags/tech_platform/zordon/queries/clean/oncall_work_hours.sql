SELECT
  id,
  oncall_team_channel_id AS id_oncall_team_channel,
  gchat_user,
  gchat_user_name,
  hours_oncall,
  nighttime_work_hours,
  daytime_work_hours,
  total_alarms,
  extra_comments,
  checkbox_incident,
  oncall_start_date AS ts_oncall_start,
  oncall_end_date AS ts_oncall_end,
  oncall_summary_date AS ts_oncall_summary
FROM
  datalake_zordon_raw.oncall_work_hours
