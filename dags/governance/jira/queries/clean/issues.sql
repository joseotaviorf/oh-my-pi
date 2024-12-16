SELECT
  changelog AS change_log,
  expand,
  fields,
  id,
  key,
  self,
  year,
  month,
  day
FROM
    datalake_jira_raw.issues
WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
