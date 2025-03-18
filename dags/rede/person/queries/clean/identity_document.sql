SELECT
    id,
    documentuuid AS uuid_document,
    person_id AS id_person,
    identification_number,
    document_validation_status,
    document_type,
    issuing_country,
    extra_info,
    attachment_path,
    document_name,
    status,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_person_raw.identity_document
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'