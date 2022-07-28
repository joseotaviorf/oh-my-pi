SELECT
  id AS id_agent,
  respondent AS agent_name,
  CAST(opened AS BIGINT) AS total_opened,
  CAST(waiting AS BIGINT) AS total_waiting,
  CAST(answered AS BIGINT) AS total_answered,
  CAST(ignored AS BIGINT) AS total_ignored,
  CAST(closed AS BIGINT) AS total_closed,
  CAST(total AS BIGINT) AS total_status_changes,
  CAST(avg_opening AS FLOAT) AS avg_opening_time,
  CAST(avg_waiting AS FLOAT) AS avg_waiting_time,
  CAST(avg_answer AS FLOAT) AS avg_answer_time, 
  CAST(avg_closed AS FLOAT) AS avg_closed_time,
  CAST(avg_total AS FLOAT) AS avg_status_changes_time,
  TO_TIMESTAMP(ts_load) AS ts_load,
  year,
  month,
  day
FROM
    datalake_stilingue_raw.report_repliers
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}