SELECT
    action_id AS id_action,
    business_group_id AS id_business_group,
    action_name,
    description,
    language, 
    source_lang AS source_language,
    created_by,
    last_updated_by AS updated_by,
    CAST(object_version_number AS INT) AS object_version_number,
    TO_TIMESTAMP(creation_date) AS ts_created,
    TO_TIMESTAMP(last_update_date) AS ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_pin_core_raw.per_actions_tl