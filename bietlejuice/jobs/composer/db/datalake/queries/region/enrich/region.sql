select
    cast(coalesce(r.id, ar.id) as bigint) as id,
    r.level,
    coalesce(r.name, ar.neighbourhood) as name,
    mr.id AS id_macro_region,
    mr.name AS macro_region_name,
    c.id AS id_city,
    coalesce(ar.city, c.name) as city_name,
    ar.city_group,
    ar.ddd as city_ddd,
    ar.region_code,
    ar.region_code_deprecated,
    ar.region_code_inspector,
    ar.state as short_region_name,
    case
        when coalesce(c.name, ar.city) in ('Rio de Janeiro', 'Campinas') then coalesce(c.name, ar.city)
        when coalesce(c.name, ar.city) in
          ('São Paulo', 'São Bernardo do Campo', 'São Caetano do Sul', 'Santo André', 'Guarulhos', 'Osasco', 'Barueri') then 'Grande São Paulo'
        else null
    end as greater_region,
    ar.regional,
    ar.regional_deprecated,
    cast(ar.tier as integer) as tier,
    r.ts_created,
    r.ts_updated
from datalake_ebdb_clean.region r
left join datalake_ebdb_clean.region mr
  on mr.id = r.id_parent_region
left join datalake_ebdb_clean.region c
  on c.id = mr.id_parent_region
left join datalake_raw.gsheets_aux_regiao ar
  on r.id = ar.id
