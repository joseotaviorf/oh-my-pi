drop view if exists vw_supply_ops_photos_costs;
create or replace view vw_supply_ops_photos_costs as
with cdre_photos as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Listing Photos'
),
filtered_properties as (
   select distinct
      vbpc.property_id,
      i.first_publication::date as listing_date
    from vw_base_property_costs vbpc
    join imovel i
      on i.id = vbpc.property_id
    where vbpc.version = 1
),
costs as (
    select
      fp.property_id,
      fp.listing_date,
      cp.dre_date as dt_cash_flow,
      cp."value" / (count(fp.property_id) over (partition by cp.dre_date))::double precision as vl_photos
    from filtered_properties fp
    join cdre_photos cp
      on cp.dre_date = date_trunc('month', fp.listing_date) + interval '1 month'
)
select
  vbpc.sk_property,
  c.property_id,
  make_date(extract(year from c.dt_cash_flow)::int, extract(month from c.dt_cash_flow)::int, 5) as dt_cash_flow,
  c.vl_photos
from costs c
join vw_base_property_costs vbpc
  on vbpc.property_id = c.property_id
where vbpc.version = 1
;