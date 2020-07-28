select
    r.id,
    r.level,
    r.name,
    mr.id AS id_macro_region,
    mr.name AS macro_region_name,
    c.id AS id_city,
    c.name AS city_name,
    r.ts_created,
    r.ts_updated
from datalake_ebdb_clean.region r
left join datalake_ebdb_clean.region mr
  on mr.id = r.id_parent_region
left join datalake_ebdb_clean.region c
  on c.id = mr.id_parent_region