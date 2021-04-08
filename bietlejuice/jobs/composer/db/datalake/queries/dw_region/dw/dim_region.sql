with
first_house as (
    select
        h.id_region,
        min(h.dt_creation) as ts_first_house_created
    from datalake_ebdb_listing.house h
    where h.id_region is not null
    group by h.id_region
),
first_booking as (
    select
        h.id_region,
        min(b.dt_booking) as dt_first_booking
    from datalake_booking.booking b
    left join datalake_ebdb_listing.house h
        on b.id_house = h.id
    left join datalake_region.region r
        on r.id = h.id_region
    group by h.id_region
)
select
    r.id as sk_region,
    r.id as id_region,
    r.id_macro_region,
    r.id_city,
    r.level,
    r.name,
    r.macro_region_name,
    r.city_name,
    r.city_group,
    r.city_ddd,
    r.region_code,
    r.region_code_deprecated,
    r.region_code_inspector,
    r.short_region_name,
    r.greater_region,
    r.regional,
    r.regional_deprecated,
    r.regional_inspection,
    r.tier,
    fb.dt_first_booking,
    fh.ts_first_house_created,
    r.ts_created,
    r.ts_updated,
    now() as ts_load
from datalake_region.region r
left join first_house fh
    on fh.id_region = r.id
left join first_booking fb
    on fb.id_region = r.id
where r.level in ('SubRegiao', 'Cidade')
