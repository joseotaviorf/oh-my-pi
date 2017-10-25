drop view if exists vw_supply_ops_inside_sales_costs;
create view vw_supply_ops_inside_sales_costs as
with cdre_inside_sales as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Inside Sales'
),
filtered_properties as (
    select distinct
      vpl.id as property_id,
      vpl.min_version_time::date as listing_date
    from vw_property_listing vpl
    join vw_dim_lead_conversion vdlc
      on vpl.id = vdlc.id_imovel
    where vdlc."type" = 'InsideSales'
),
costs as (
    select
      fp.property_id,
      fp.listing_date,
      cis.dre_date as dt_cash_flow,
      cis."value" / (count(fp.property_id) over (partition by cis.dre_date))::double precision as vl_photos
    from filtered_properties fp
    join cdre_inside_sales cis
      on cis.dre_date = date_trunc('month', fp.listing_date)
)
select
  vbpc.sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_photos
from costs c
join vw_base_property_costs vbpc
  on vbpc.property_id = c.property_id
    and c.listing_date = vbpc.min_version_time::date
;