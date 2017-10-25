drop view if exists vw_liquidity_ops_field_ops_costs;
create view vw_liquidity_ops_field_ops_costs as
with cdre_field_ops as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Field Ops'
),
filtered_visits as (
    select
      id as visit_id,
      imovel_id as property_id,
      data as dt
    from booking
    where tipo = 'Visita'
        and status = 'Realizado'
),
costs as (
    select
      fv.property_id,
      fv.dt,
      cfo.dre_date as dt_cash_flow,
      cfo."value" / (count(fv.property_id) over (partition by cfo.dre_date))::double precision as vl_field_ops
    from filtered_visits fv
    join cdre_field_ops cfo
      on cfo.dre_date = date_trunc('month', fv.dt)
)
select
  vbpc.sk_property,
  c.property_id,
  c.dt_cash_flow,
  sum(c.vl_field_ops) as vl_field_ops
from costs c
join vw_base_property_costs vbpc
  on vbpc.property_id = c.property_id
    and c.dt between vbpc.min_version_time and vbpc.max_version_time
group by vbpc.sk_property, c.property_id, c.dt_cash_flow
;