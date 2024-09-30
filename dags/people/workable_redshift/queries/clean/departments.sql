SELECT
  id,
  parent_id AS id_parent,
  name,
  created_at AS ts_created,
  updated_at AS ts_updated,
  NOW() AS ts_load
FROM
  datalake_workable_redshift_raw.departments
WHERE
  MAKE_DATE(YEAR, MONTH, DAY) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY 
  updated_at = MAX(updated_at) OVER (
    PARTITION BY
      id
  )