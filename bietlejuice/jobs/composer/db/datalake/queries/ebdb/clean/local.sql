SELECT
    id,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created,
    lat,
    latlng AS lat_lng,
    lng,
    nome AS name,
    referenciaExterna AS external_reference,
    tipo AS type,
    active AS is_active,
    comment,
    slug,
    region_id AS id_region
FROM
    datalake_ebdb_raw.local
