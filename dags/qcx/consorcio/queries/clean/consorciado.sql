SELECT 
    id,
    uuid,
    external_id AS id_external,
    person_uuid AS uuid_person,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM 
    datalake_consorcio_raw.consorciado 