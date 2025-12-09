SELECT
    id,
    company_id AS id_company,
    contact_uuid AS uuid_contact,
    type,
    name,
    value,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM datalake_company_raw.contact
