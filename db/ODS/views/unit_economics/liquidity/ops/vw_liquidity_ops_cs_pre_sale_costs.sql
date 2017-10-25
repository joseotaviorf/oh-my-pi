drop view if exists vw_liquidity_ops_cs_pre_sale_costs;
create or replace view vw_liquidity_ops_cs_pre_sale_costs as
with cdre_cs_pre_sale as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Customer Support (pre-sale)'
),

-- USE VW_BASE_PROPERTY_COSTS
filtered_properties as (
    select distinct
      id as property_id,
      min_version_time::date,
      max_version_time::date
    from vw_property_listing
    where last_status_version = 'publicado'
),
costs as (
    select
      fp.property_id,
      fp.min_version_time,
      fp.max_version_time,
      cps.dre_date as dt_cash_flow,
      cps."value" / (count(fp.property_id) over (partition by cps.dre_date))::double precision as vl_cs_pre_sale
    from filtered_properties fp
    join cdre_cs_pre_sale cps
      on cps.dre_date between date_trunc('month', fp.min_version_time) and date_trunc('month', fp.max_version_time)
)
select
  vbpc.sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_cs_pre_sale
from costs c
join vw_base_property_costs vbpc
  on vbpc.property_id = c.property_id
    and c.min_version_time = vbpc.min_version_time
    and c.max_version_time = vbpc.max_version_time
;