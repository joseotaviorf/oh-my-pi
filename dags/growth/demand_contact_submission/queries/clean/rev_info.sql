SELECT
  rev,
  FROM_UNIXTIME(revtstmp/1000) AS ts_rev,
  YEAR(ts_rev) AS year,
  MONTH(ts_rev) AS month,
  DAY(ts_rev) as day
FROM
  datalake_demand_contact_submission_raw.revinfo
