SELECT
  id_agent AS sk_agent,
  MD5(department) AS sk_department,
  CAST(DATE_FORMAT(dt_metric_reference, 'yyyyMMdd') AS BIGINT) AS sk_date,
  closed_demand,
  solved_demand,
  tickets_solved_in_time,
  tickets_not_solved_in_time,
  sum_csat_satisfied_score,
  sum_csat_dissatisfied_score,
  total_tickets_resolution,
  total_tickets_answered_resolution,
  total_tickets_with_csat_score,
  ra_score_sum,
  ra_would_do_business_again,
  ra_solved_tickets,
  ra_total_tickets_rated,
  dt_metric_reference,
  year,
  month,
  day
FROM
  datalake_analyst_ranking.analyst_metrics
WHERE
  (
    year = {year}
    AND month = {month}
    AND day = {day}
  )
  OR (
    year = YEAR(DATE('{year}-{month}-{day}') - INTERVAL 1 DAY)
    AND month = MONTH(DATE('{year}-{month}-{day}') - INTERVAL 1 DAY)
    AND day = DAY(DATE('{year}-{month}-{day}') - INTERVAL 1 DAY)
  )
