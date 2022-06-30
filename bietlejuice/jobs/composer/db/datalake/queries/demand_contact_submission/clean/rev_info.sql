SELECT 
  rev,
  FROM_UNIXTIME(revtstmp/1000) as ts_rev,
  year,
  month,
  day
FROM
  datalake_demand_contact_submission_raw.revinfo
WHERE
  year = {year}
  AND month = {month}
  AND day = {day}