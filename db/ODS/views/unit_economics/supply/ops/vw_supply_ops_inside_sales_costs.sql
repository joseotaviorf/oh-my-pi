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
      sk_property,
      property_id,
      min_version_time::date as listing_date
    from vw_base_property_costs
    where version = 1
),
costs as (
    select
      fp.sk_property,
      fp.property_id,
      fp.listing_date,
      cis.dre_date as dt_cash_flow,
      cis."value" / (count(fp.property_id) over (partition by cis.dre_date))::double precision as vl_inside_sales
    from filtered_properties fp
    join cdre_inside_sales cis
      on cis.dre_date = date_trunc('month', fp.listing_date) + interval '1 month'
)
select
  sk_property,
  property_id,
  dt_cash_flow as dt_cash_flow,
  vl_inside_sales
from costs c
;