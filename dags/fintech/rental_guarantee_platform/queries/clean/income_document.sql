SELECT
    id,
    person_id AS id_person,
    documentuuid AS uuid_document,
    document_type,
    income_nature,
    extra_info,
    attachment_path,
    document_name,
    validation_status,
    status,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.income_document

QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
