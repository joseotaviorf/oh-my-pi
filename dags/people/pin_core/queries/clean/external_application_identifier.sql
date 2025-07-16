SELECT
    ext_identifier_id AS id_external_identifier,
    person_id AS id_person,
    enterprise_id AS id_enterprise,
    ext_identifier_type AS type_external_identifier,
    ext_identifier_number AS number_external_identifier,
    ext_identifier_seq AS sequence_external_identifier,
    CAST(object_version_number AS INT) AS object_version_number,
    created_by,
    last_updated_by AS updated_by,
    TO_DATE(date_from) AS dt_started,
    TO_DATE(date_to) AS dt_ended,
    TO_TIMESTAMP(creation_date) AS ts_created,
    TO_TIMESTAMP(last_update_date) AS ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_pin_core_raw.per_ext_app_identifiers