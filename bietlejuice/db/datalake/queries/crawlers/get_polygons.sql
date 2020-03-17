select
    r.id_region as id,
    r.name as region,
    c.name as city,
    pr.polygon as poly
from
    datalake_ebdb_clean_prod.polygon_region pr
join
    datalake_ebdb_clean_prod.region r
    on r.id_region = pr.id_region
join
    datalake_ebdb_clean_prod.region m
    on m.id_region = r.id_parent_region
join
    datalake_ebdb_clean_prod.region c
    on c.id_region = m.id_parent_region
where
    r.level = 'SubRegiao'