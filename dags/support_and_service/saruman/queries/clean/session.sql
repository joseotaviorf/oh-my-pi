SELECT
    id,
    support_case_id AS id_support_case,
    user_id AS id_user,
    department,
    tags,
    status,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_saruman_raw.session
WHERE
    yMAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
