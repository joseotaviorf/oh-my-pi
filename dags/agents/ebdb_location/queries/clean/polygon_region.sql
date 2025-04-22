SELECT
    id,
    STRING(ST_GEOMFROMWKB(UNBASE64(poligono.wkb))) AS polygon,
    regiao_id AS id_region,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created
FROM
    datalake_ebdb_raw.poligonoregiao
