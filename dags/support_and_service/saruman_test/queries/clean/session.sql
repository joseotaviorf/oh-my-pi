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
    datalake_saruman_test_raw.session
