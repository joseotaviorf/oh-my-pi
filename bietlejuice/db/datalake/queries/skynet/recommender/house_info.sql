with base as (
  select
    i.id as house_id,
    try(cast(i.aluguel as double)) as rent,
    try(cast(i.condominio as double)) as condominium,
    try(cast(i.iptu as double)) as iptu,
    try(cast(i.numeroQuartos as smallint)) as bedrooms,
    try(cast(i.numeroBanheiros as smallint)) as bathrooms,
    try(cast(i.numeroVagas as smallint)) as parking_slots,
    try(cast(i.numeroSuites as smallint)) as suites,
    try(cast(i.areaTotal as smallint)) as total_area,
    try(cast(i.lat as double)) as lat,
    try(cast(i.lng as double)) as lng,
    mr.id as region_id,
    mr.macroid as macro_id,
    mr.cidadeid as city_id
  from datalake_raw.ebdb_imovel i
  left join datalake_raw.ebdb_mapregiao mr
      on mr.id = i.regiao_id
  where if(firstPublication <> '', firstPublication) is not null
)
select
  *,
  rent + condominium + iptu as total_price,
  (rent + condominium + iptu) / total_area as price_m2
from base
