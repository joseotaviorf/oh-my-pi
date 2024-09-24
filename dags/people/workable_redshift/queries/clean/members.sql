SELECT
    id,
    api_id AS id_api,
    `role`,
    email,
    `name`,
    headline,
    active AS is_active,
    member_created_at AS ts_member_created,
    updated_at AS ts_updated,
    NOW() AS ts_load
FROM
    datalake_workable_redshift_raw.members
WHERE 
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY 
    updated_at = MAX(updated_at) OVER (PARTITION BY id)