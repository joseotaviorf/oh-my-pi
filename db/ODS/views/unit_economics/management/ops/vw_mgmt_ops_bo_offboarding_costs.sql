drop view if exists vw_mgmt_ops_bo_offboarding_costs;
create or replace view vw_mgmt_ops_bo_offboarding_costs as
with cdre_offboarding as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Back-Office (offboarding)'
),
filtered_contracts as (
    select distinct
      imovel_id as property_id,
      (max(coalesce("dataRescisao", "dataFimContratoPrevisto")) over (partition by imovel_id))::date as end_date
    from contract
    where tipo = 'FullService'
      and ("dataRescisao" is not null
           or "dataFimContratoPrevisto" is not null)
),
costs as (
    select
      fc.property_id,
      fc.end_date,
      co.dre_date as dt_cash_flow,
      co."value" / (count(fc.property_id) over (partition by co.dre_date))::double precision as vl_bo_offboarding
    from filtered_contracts fc
    join cdre_offboarding co
      on co.dre_date = date_trunc('month', fc.end_date) + interval '1 month'
)
select
  coalesce(vbpc.sk_property, (c.property_id || '001')::bigint) as sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_bo_offboarding
from costs c
left join vw_base_property_costs vbpc
  on vbpc.property_id = c.property_id
    and c.end_date between vbpc.min_version_time and vbpc.max_version_time
;