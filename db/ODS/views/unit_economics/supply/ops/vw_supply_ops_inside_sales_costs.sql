drop view if exists vw_supply_ops_inside_sales_costs;
create or replace view vw_supply_ops_inside_sales_costs as
with cdre_inside_sales as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Inside Sales'
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
      cis.dre_date as dt_cash_flow,
      cis."value" / (count(fp.property_id) over (partition by cis.dre_date))::double precision as vl_inside_sales
    from filtered_properties fp
    join cdre_inside_sales cis
      on cis.dre_date = date_trunc('month', fp.listing_date) + interval '1 month'
)
select
  vbpc.sk_property,
  c.property_id,
  c.dt_cash_flow as dt_cash_flow,
  c.vl_inside_sales
from costs c
join vw_base_property_costs vbpc
  on vbpc.property_id = c.property_id
where vbpc.version = 1
;