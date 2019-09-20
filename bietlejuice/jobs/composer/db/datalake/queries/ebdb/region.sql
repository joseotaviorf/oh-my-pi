SELECT
    r.id AS id_region,
    r.criadaEm AS ts_created,
    r.atualizadoEm AS ts_updated,
    r.nivel AS level,
    r.nome AS name,
    mr.id AS id_macro,
    mr.nome AS macro_name,
    c.id AS id_city,
    c.nome AS city_name,
    now() AS dt_timestamp
from
    datalake_ebdb_raw.regiao r
    LEFT JOIN datalake_ebdb_raw.regiao mr ON
        mr.id = r.regiaoPai_id
    LEFT JOIN datalake_ebdb_raw.regiao c ON
        c.id = mr.regiaoPai_id
WHERE
    r.nivel IN ('SubRegiao', 'Cidade')
