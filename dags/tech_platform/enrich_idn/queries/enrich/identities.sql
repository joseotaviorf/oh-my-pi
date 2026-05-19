WITH scoped AS (
  SELECT
    id_identity,
    nm_identity,
    nm_display,
    ds_work_email,
    ds_lifecycle_state,
    ds_identity_status,
    ds_employee_number,
    ds_cost_center,
    ds_last_login_sso,
    nm_manager,
    nm_department,
    ds_worker_type,
    nm_company,
    nm_job,
    ds_location,
    dt_start,
    dt_end,
    ts_created,
    ts_modified,
    js_raw_attributes,
    year,
    month,
    day
  FROM
    datalake_idn_clean.identities
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
max_reading AS (
  SELECT
    MAX(MAKE_DATE(year, month, day)) AS d
  FROM
    scoped
),
latest_partition AS (
  SELECT
    scoped.id_identity,
    scoped.nm_identity,
    scoped.nm_display,
    scoped.ds_work_email,
    scoped.ds_lifecycle_state,
    scoped.ds_identity_status,
    scoped.ds_employee_number,
    scoped.ds_cost_center,
    scoped.ds_last_login_sso,
    scoped.nm_manager,
    scoped.nm_department,
    scoped.ds_worker_type,
    scoped.nm_company,
    scoped.nm_job,
    scoped.ds_location,
    scoped.dt_start,
    scoped.dt_end,
    scoped.ts_created,
    scoped.ts_modified,
    scoped.js_raw_attributes,
    scoped.year,
    scoped.month,
    scoped.day
  FROM
    scoped
    INNER JOIN max_reading
        ON MAKE_DATE(scoped.year, scoped.month, scoped.day) = max_reading.d
)
SELECT
  id_identity,
  nm_identity,
  nm_display,
  ds_work_email,
  ds_lifecycle_state,
  ds_identity_status,
  ds_employee_number,
  ds_cost_center,
  ds_last_login_sso,
  nm_manager,
  nm_department,
  ds_worker_type,
  nm_company,
  nm_job,
  ds_location,
  dt_start,
  dt_end,
  ts_created,
  ts_modified,
  js_raw_attributes,
  year,
  month,
  day
FROM
  latest_partition
QUALIFY
  ROW_NUMBER() OVER (
    PARTITION BY id_identity
    ORDER BY
      ts_modified DESC NULLS LAST,
      nm_display ASC NULLS LAST
  ) = 1
