drop view if exists unit_economics.vw_liquidity_ops_cs_pre_sale_costs;
create or replace view unit_economics.vw_liquidity_ops_cs_pre_sale_costs as
with cdre_cs_pre_sale as (
    select
      dre_value,
      dre_date
    from unit_economics.vw_base_dre_costs
    where dre_category = 'Customer Support (pre-sale)'
),
qt_nulls as (
  select
    property_id,
    dt,
    sum(qt) as qt
  from unit_economics.base_ticket_task
  where property_id = -1
    and group_name = 'Customer Support (pre-sale)'
  group by property_id, dt
),
calculated_qt as (
  select
    tt.property_id,
    tt.dt,
    tt.qt
  from unit_economics.base_ticket_task tt
  where tt.group_name = 'Customer Support (pre-sale)'
    and property_id != -1
),
filtered_properties_prev as (
    select distinct
        sk_property,
        property_id,
        publication_date::date,
        min_version_time::date,
		case
			when min_version_time + interval '1 year' >= max_version_time
				then max_version_time
			when min_version_time + interval '1 year' >= now()
				then now()
			else
				min_version_time + interval '1 year'
		end as max_liquidity_date
    from unit_economics.vw_base_property_costs
    where status = 'publicado'
),
filtered_properties as (
  select distinct
    fpp.sk_property,
    fpp.property_id,
    cps.dre_date as dt
  from filtered_properties_prev fpp
    join cdre_cs_pre_sale cps
      on cps.dre_date between date_trunc('month', fpp.min_version_time) + interval '1 month'
                        and date_trunc('month', fpp.max_liquidity_date) + interval '1 month'
),
ratio as (
  select distinct
    fp.dt,
    qn.qt / count(fp.property_id) over (partition by fp.dt) as qt
  from filtered_properties fp
  left join qt_nulls qn
    on fp.dt = qn.dt
),
gen_contracts as (
	select
	    fp.sk_property,
		fp.property_id,
		fp.dt,
		r.qt as qt_gen
	from
  	filtered_properties fp
  left join ratio r
  	on fp.dt = r.dt
),
espec_gen_prev as (
  select
    fp.sk_property,
    fp.property_id,
    cqt.dt as dt,
    cqt.qt as qt
  from
  	filtered_properties fp
  join calculated_qt cqt
    on cqt.property_id = fp.property_id
  union
  select
  	*
	from gen_contracts
),
espec_gen as (
	select
	    sk_property,
		property_id,
		dt,
		sum(qt) as qt
	from espec_gen_prev
	group by
		sk_property, property_id, dt
),
tt_costs as (
    select
      eg.sk_property,
      eg.property_id,
      eg.dt,
      cps.dre_date as dt_cash_flow,
      cps.dre_value * eg.qt / (sum(eg.qt) over (partition by cps.dre_date))::double precision as vl_cs_pre_sale
    from espec_gen eg
    join cdre_cs_pre_sale cps
      on cps.dre_date = eg.dt + interval '1 month'
),
property_costs as (
    select
      fp.sk_property,
      fp.property_id,
      fp.dt,
      cps.dre_date as dt_cash_flow,
      cps.dre_value / (count(fp.property_id) over (partition by cps.dre_date))::double precision as vl_cs_pre_sale
    from filtered_properties fp
    join cdre_cs_pre_sale cps
      on cps.dre_date = fp.dt
),
full_costs as (
  select distinct
    sk_property,
    property_id,
    dt,
    dt_cash_flow,
    vl_cs_pre_sale
  from tt_costs
  where dt = dt_cash_flow

  union

  select distinct
    sk_property,
    property_id,
    dt,
    dt_cash_flow,
    vl_cs_pre_sale
  from property_costs
  where dt = dt_cash_flow
)
select
  vbpc.sk_property,
  fc.property_id,
  fc.dt_cash_flow,
  fc.vl_cs_pre_sale
from full_costs fc
join unit_economics.vw_base_property_costs vbpc
  on vbpc.sk_property = fc.sk_property
;