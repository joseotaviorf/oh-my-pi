SELECT
    -- ids
    id,
    member_id AS id_member,

    -- non-metrics
    role,
    country_code,
    state_code,
    city,
    subregion,
    zip_code,

    -- timestamps
    NOW() AS ts_load

FROM
    datalake_workable_redshift_raw.collaboration_rules