SELECT
    id,
    case_pendency_id AS id_case_pendency,
    parent_support_case_id AS id_parent_support_case,
    task_pendency_id AS id_task_pendency,
    status,
    title,
    type,
    external_url,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_saruman_raw.pendency
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
