with base as (
  select
    i.id as house_id,
    try(cast(i.rent as double)) as rent,
    try(cast(i.condo as double)) as condominium,
    try(cast(i.iptu as double)) as iptu,
    try(cast(i.bedrooms as smallint)) as bedrooms,
    try(cast(i.bathrooms as smallint)) as bathrooms,
    try(cast(i.parking_slots as smallint)) as parking_slots,
    try(cast(i.suites as smallint)) as suites,
    try(cast(i.total_area as smallint)) as total_area,
    try(cast(i.lat as double)) as lat,
    try(cast(i.lng as double)) as lng,
    mr.id as region_id,
    mr.id_macro as macro_id,
    mr.id_city as city_id
  from datalake_ebdb_clean_prod.house i
  left join datalake_ebdb_clean_prod.map_region mr
      on mr.id = i.id_region
  where dt_first_publication is not null
)
select
  *,
  rent + condominium + iptu as total_price,
  (rent + condominium + iptu) / total_area as price_m2
from base