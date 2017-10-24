drop view if exists vw_supply_ops_photos_costs;
create view vw_supply_ops_photos_costs as
with cdre_photos as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Photos'
),
filtered_properties as (
    select distinct
      id as property_id,
      min_version_time::date as listing_date
    from vw_property_listing
),
costs as (
    select
      fp.property_id,
      fp.listing_date,
      cp.dre_date + interval '1 month' as dt_cash_flow,
      cp."value" / (count(fp.property_id) over (partition by cp.dre_date))::double precision as vl_photos
    from filtered_properties fp
    join cdre_photos cp
      on cp.dre_date = date_trunc('month', fp.listing_date)
)
select
  vbpc.sk_property,
  c.property_id,
  make_date(extract(year from c.dt_cash_flow)::int, extract(month from c.dt_cash_flow)::int, 5) as dt_cash_flow,
  c.vl_photos
from costs c
join vw_base_property_costs vbpc
  on vbpc.property_id = c.property_id
    and c.listing_date = vbpc.min_version_time::date
;