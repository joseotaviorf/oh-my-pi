drop view if exists vw_mgmt_ops_bo_onboarding_costs;
create view vw_mgmt_ops_bo_onboarding_costs as
with cdre_onboarding as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Back-Office (onboarding)'
),
filtered_contracts as (
    select distinct
      imovel_id as property_id,
      (max("dataAssinado") over w)::date as "from",
      (max("dataEntrada") over w)::date as "to"
    from contract
    where tipo = 'FullService'
      and ("dataAssinado" is not null
           or "dataEntrada" is not null)
    window w as (partition by imovel_id)
),
costs as (
    select
      fc.property_id,
      fc."from",
      fc."to",
      co.dre_date as dt_cash_flow,
      co."value" / (count(fc.property_id) over (partition by co.dre_date))::double precision as vl_bo_onboarding
    from filtered_contracts fc
    join cdre_onboarding co
      on co.dre_date between date_trunc('month', fc."from") and co.dre_date = date_trunc('month', fc."to")
)
select
  vbpc.sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_bo_onboarding
from costs c
join vw_base_property_costs vbpc
  on vbpc.property_id = c.property_id
    and c."from" >= vbpc.min_version_time
    and c."to" <= vbpc.max_version_time
;