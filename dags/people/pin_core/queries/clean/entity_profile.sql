SELECT
    legal_entity_id AS id_legal_entity,
    party_id AS id_party,
    geography_id AS id_geography,
    enterprise_id AS id_enterprise,
    legal_entity_identifier AS id_business_legal_entity,
    UPPER(name) AS legal_entity_name,
    attribute_category,
    le_information_context AS legal_information_context,
    transacting_entity_flag = 'Y' AS is_transacting_entity,
    psu_flag = 'Y' AS is_payroll_statutory_unit,
    legal_employer_flag = 'Y' AS is_legal_employer,
    created_by,
    last_updated_by AS updated_by,
    CAST(object_version_number AS INT) AS object_version_number,
    TO_DATE(effective_from) AS dt_effective_started,
    TO_TIMESTAMP(creation_date) AS ts_created,
    TO_TIMESTAMP(last_update_date) AS ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_pin_core_raw.xle_entity_profiles