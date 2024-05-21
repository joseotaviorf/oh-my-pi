SELECT
  rev,
  FROM_UNIXTIME(revtstmp/1000) AS ts_rev,
  year,
  month,
  day
FROM
  datalake_demand_contact_submission_raw.revinfo
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
