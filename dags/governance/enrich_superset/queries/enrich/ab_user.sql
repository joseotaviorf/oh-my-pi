WITH u AS (
  SELECT 
    *,
    RANK() OVER (PARTITION BY id ORDER BY ts_changed DESC) most_recent_rank
  from datalake_superset_clean.ab_user
)
SELECT 
  id,
  id_user_created,
  id_user_changed,
  first_name,
  last_name,
  username,
  email,
  is_active,
  login_count,
  fail_login_count,
  ts_created,
  ts_changed,
  ts_last_login,
  year,
  month,
  day
FROM u 
WHERE most_recent_rank = 1