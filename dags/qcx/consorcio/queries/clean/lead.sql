SELECT
    id,
    session_id AS id_session,
    uuid,
    person_uuid AS uuid_person,
    name,
    phone,
    email,
    metadata,
    source,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_term,
    utm_content,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_consorcio_raw.lead
