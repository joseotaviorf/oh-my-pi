drop view if exists vw_liquidity_ops_bo_pre_sale_costs;
create or replace view vw_liquidity_ops_bo_pre_sale_costs as
with cdre_bo_pre_sale as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Back-Office (pre-sale)'
),
filtered_contracts as (
    select distinct
      imovel_id as property_id,
      (max("criadoEm") over (partition by imovel_id))::date as created_date,
      (max("dataAssinado") over (partition by imovel_id))::date as signature_date
    from contract
    where tipo = 'FullService'
      and ("criadoEm" is not null
           or "dataAssinado" is not null)
),
costs as (
    select
      fc.property_id,
      fc.created_date,
      fc.signature_date,
      cps.dre_date as dt_cash_flow,
      cps."value" / (count(fc.property_id) over (partition by cps.dre_date))::double precision as vl_bo_pre_sale
    from filtered_contracts fc
    join cdre_bo_pre_sale cps
      on cps.dre_date = date_trunc('month', fc.created_date)
         or  cps.dre_date = date_trunc('month', fc.signature_date)
)
select
  max(vbpc.sk_property) as sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_bo_pre_sale
from costs c
join vw_base_property_costs vbpc
  on vbpc.property_id = c.property_id
    and (c.created_date between vbpc.min_version_time and vbpc.max_version_time
         or c.signature_date between vbpc.min_version_time and vbpc.max_version_time)
group by c.property_id, c.dt_cash_flow, c.vl_bo_pre_sale
;