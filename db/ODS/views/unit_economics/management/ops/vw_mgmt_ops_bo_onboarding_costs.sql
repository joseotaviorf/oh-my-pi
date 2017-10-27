drop view if exists vw_mgmt_ops_bo_onboarding_costs;
create or replace view vw_mgmt_ops_bo_onboarding_costs as
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
      case
        when "dataAssinado"::date > "dataEntrada"::date
          then "dataEntrada"::date
        else "dataAssinado"::date
      end as "from",
      case
        when "dataAssinado"::date > "dataEntrada"::date
          then "dataAssinado"::date
        else "dataEntrada"::date
      end as "to"
    from contract
    where tipo = 'FullService'
      and "dataAssinado" is not null
      and "dataEntrada" is not null
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
      on co.dre_date between date_trunc('month', fc."from") and date_trunc('month', fc."to")
)
select
  coalesce(vbpc.sk_property, (c.property_id || '001')::bigint )as sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_bo_onboarding
from costs c
left join vw_base_property_costs vbpc
  on vbpc.property_id = c.property_id
    and c."from" >= vbpc.min_version_time
    and c."to" <= vbpc.max_version_time
    where vbpc.sk_property is null
;
