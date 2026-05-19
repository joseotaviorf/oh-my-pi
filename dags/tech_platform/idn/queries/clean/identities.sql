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
    TRY_CAST(dt_start AS DATE) AS dt_start,
    TRY_CAST(dt_end AS DATE) AS dt_end,
    TRY_CAST(ts_created AS TIMESTAMP) AS ts_created,
    TRY_CAST(ts_modified AS TIMESTAMP) AS ts_modified,
    js_raw_attributes,
    year,
    month,
    day
FROM
    datalake_idn_raw.identities
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
