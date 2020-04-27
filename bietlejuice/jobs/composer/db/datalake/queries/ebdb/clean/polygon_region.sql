SELECT
    id,
    poligono AS polygon,
    regiao_id AS id_region,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created
FROM
    datalake_ebdb_raw.poligonoregiao
