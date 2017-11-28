drop view if exists vw_mgmt_ops_cs_post_sale_costs;
create or replace view vw_mgmt_ops_cs_post_sale_costs as
with cdre_cs_post_sale as (
    select
      dre_value,
      dre_date
    from vw_base_dre_costs
    where dre_category = 'Customer Support (post-sale)'
),
qt_nulls as (
  select
    property_id,
    dt,
    sum(qt) as qt
  from vw_base_ticket_task
  where property_id = -1
    and group_name = 'Customer Support (post-sale)'
  group by property_id, dt
),
calculated_qt as (
  select
    tt.property_id,
    tt.dt,
    tt.qt
  from vw_base_ticket_task tt
  where tt.group_name = 'Customer Support (post-sale)'
    and property_id != -1
),
filtered_contracts_prev as (
    select distinct
      imovel_id as property_id,
      "dataInicio" as start_date,
      (max(coalesce("dataRescisao", "dataFimContratoPrevisto")) over w)::date as end_date
    from contract c
    where tipo = 'FullService'
      and "dataInicio" is not null
      and ("dataRescisao" is not null
            or "dataFimContratoPrevisto" is not null)
    window w as (partition by imovel_id)
),
filtered_contracts as (
  select distinct
    fcp.property_id,
    cps.dre_date - interval '1 month' as dt
  from filtered_contracts_prev fcp
    join cdre_cs_post_sale cps
      on cps.dre_date between date_trunc('month', fcp.start_date) + interval '1 month'
                        and date_trunc('month', fcp.end_date) + interval '1 month'
),
ratio as (
  select distinct
    fc.dt,
    qn.qt / count(fc.property_id) over (partition by fc.dt) as qt
  from filtered_contracts fc
  left join qt_nulls qn
    on fc.dt = qn.dt
),
espec_gen as (
  select
    fc.property_id,
    coalesce(fc.dt, cqt.dt) as dt,
    coalesce(cqt.qt, 0) + r.qt as qt
  from calculated_qt cqt
  right join filtered_contracts fc
    on cqt.property_id = fc.property_id
     and cqt.dt = fc.dt
  join ratio r
    on r.dt = fc.dt
),
tt_costs as (
    select
      eg.property_id,
      eg.dt,
      cps.dre_date as dt_cash_flow,
      cps.dre_value * eg.qt / (sum(eg.qt) over (partition by cps.dre_date))::double precision as vl_cs_post_sale
    from espec_gen eg
    join cdre_cs_post_sale cps
      on cps.dre_date = eg.dt + interval '1 month'
),
contract_costs as (
    select
      fc.property_id,
      fc.dt,
      cps.dre_date as dt_cash_flow,
      cps.dre_value / (count(fc.property_id) over (partition by cps.dre_date))::double precision as vl_cs_post_sale
    from filtered_contracts fc
    join cdre_cs_post_sale cps
      on cps.dre_date = fc.dt
),
full_costs as (
  select distinct
    property_id,
    dt,
    dt_cash_flow,
    vl_cs_post_sale
  from tt_costs
  where dt = dt_cash_flow

  union

  select distinct
    property_id,
    dt,
    dt_cash_flow,
    vl_cs_post_sale
  from contract_costs
  where dt = dt_cash_flow
)
select
  coalesce(vbpc.sk_property, (fc.property_id || '001')::bigint) as sk_property,
  fc.property_id,
  fc.dt_cash_flow,
  fc.vl_cs_post_sale
from full_costs fc
left join vw_base_property_costs vbpc
  on vbpc.property_id = fc.property_id
    and fc.dt - interval '1 month' between vbpc.min_version_time and vbpc.max_version_time
;