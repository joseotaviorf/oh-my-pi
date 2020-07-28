select
    r.id,
    r.name as region,
    r.city_name as city,
    pr.polygon as poly
from
    datalake_ebdb_clean_prod.polygon_region pr
join datalake_ebdb_region_prod.region r
    on r.id = pr.id_region
where r.level = 'SubRegiao'