SELECT
    element_type_id AS id_element_type,
    enterprise_id AS id_enterprise,
    language,
    source_lang AS source_language,
    element_name,
    reporting_name,
    description,
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
    datalake_pin_compensation_raw.pay_element_types_tl
