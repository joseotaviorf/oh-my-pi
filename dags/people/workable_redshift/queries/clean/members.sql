SELECT
    id,
    api_id AS id_api,
    "role",
    email,
    "name",
    headline,
    active AS is_active,
    member_created_at AS ts_member_created,
    updated_at AS ts_updated,
    NOW() AS ts_load
FROM
    datalake_workable_redshift_raw.members
WHERE 
    DATE(updated_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')