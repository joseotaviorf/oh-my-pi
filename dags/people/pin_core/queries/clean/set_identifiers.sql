SELECT
    enterprise_id AS id_enterprise,
    set_id AS id_set,
    set_code,
    set_name,
    language,
    source_lang AS source_language,
    created_by,
    last_updated_by AS updated_by,
    TO_TIMESTAMP(creation_date) AS ts_created,
    TO_TIMESTAMP(last_update_date) AS ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_pin_core_raw.fnd_setid_sets