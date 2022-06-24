SELECT
  conversations, 
  cases, 
  statusesChanges AS status_changes, 
  interactions,
  ts_load,
  year,
  month,
  day
FROM
    datalake_stilingue_raw.calls_report
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}