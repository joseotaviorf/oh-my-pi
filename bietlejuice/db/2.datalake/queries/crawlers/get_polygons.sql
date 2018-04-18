select
    r.id as id,
    r.nome as region,
    c.nome as city,
    pr.poligono as poly
from
    datalake_raw.ebdb_poligonoregiao pr
join
    datalake_raw.ebdb_regiao r
    on r.id = pr.regiao_id
join
    datalake_raw.ebdb_regiao m
    on m.id = r.regiaopai_id
join
    datalake_raw.ebdb_regiao c
    on c.id = m.regiaopai_id
where
    r.nivel = 'SubRegiao'