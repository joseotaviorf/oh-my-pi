SELECT 
    id,
    consorciado_id AS id_consorciado,
    external_quota_id AS id_external_quota,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM 
    datalake_consorcio_raw.consorciado_quota 