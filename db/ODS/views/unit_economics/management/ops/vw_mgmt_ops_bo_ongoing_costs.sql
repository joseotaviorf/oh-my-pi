drop view if exists vw_mgmt_ops_bo_ongoing_costs;
create view vw_mgmt_ops_bo_ongoing_costs as
with cdre_ongoing as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Back-Office (ongoing)'
),
filtered_contracts as (
    select distinct
      imovel_id as property_id,
      "dataInicio" as start_date,
      (max(coalesce("dataRescisao", "dataFimContratoPrevisto")) over w)::date as end_date
    from contract
    where tipo = 'FullService'
      and "dataInicio" is not null
      and ("dataRescisao" is not null
            or "dataFimContratoPrevisto" is not null)
    window w as (partition by imovel_id)
),
costs as (
    select
      fc.property_id,
      fc.start_date,
      fc.end_date,
      co.dre_date as dt_cash_flow,
      co."value" / (count(fc.property_id) over (partition by co.dre_date))::double precision as vl_bo_ongoing
    from filtered_contracts fc
    join cdre_ongoing co
      on co.dre_date between date_trunc('month', fc.start_date) and date_trunc('month', fc.end_date)
)
select
  vbpc.sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_bo_ongoing
from costs c
join vw_base_property_costs vbpc
  on vbpc.property_id = c.property_id
    and c.start_date >= vbpc.min_version_time
    and c.end_date <= vbpc.max_version_time
;