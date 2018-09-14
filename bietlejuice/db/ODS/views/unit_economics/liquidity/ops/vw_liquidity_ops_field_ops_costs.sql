drop view if exists unit_economics.vw_liquidity_ops_field_ops_costs;
create or replace view unit_economics.vw_liquidity_ops_field_ops_costs as
with cdre_field_ops as (
    select
      dre_value,
      dre_date
    from unit_economics.vw_base_dre_costs
    where dre_category like 'Field Operation%'
),
filtered_visits as (
    select
      b.id as visit_id,
      vbpc.sk_property,
      b.imovel_id as property_id,
      b.data as dt
    from unit_economics.vw_base_property_costs vbpc
	left join booking b
	  on vbpc.property_id = b.imovel_id
	    and b.data between vbpc.min_version_time and vbpc.max_version_time
    where
		b.tipo = 'Visita'
	and -- visits before 2016-02 dont have fup
		(
		case
			when b.status = 'Realizado' then true
			when (b.status = 'Marcado' and data <= '2016-02-25'::date) then true
			else false
		end
		) = true
	and -- check for max liquidity date
		b.data <=
		(case
			when min_version_time + interval '1 year' >= max_version_time
				then max_version_time
			when min_version_time + interval '1 year' >= now()
				then now()
			else
				min_version_time + interval '1 year'
		end)
),
costs as (
    select
      fv.sk_property,
      fv.property_id,
      fv.dt,
      cfo.dre_date as dt_cash_flow,
      cfo.dre_value / (count(fv.property_id) over (partition by cfo.dre_date))::double precision as vl_field_ops
    from filtered_visits fv
    join cdre_field_ops cfo
      on cfo.dre_date = (date_trunc('month', fv.dt) + interval '1 month')::date
)
select
  c.sk_property,
  c.property_id,
  c.dt_cash_flow,
  sum(c.vl_field_ops) as vl_field_ops
from costs c
group by c.sk_property, c.property_id, c.dt_cash_flow
;