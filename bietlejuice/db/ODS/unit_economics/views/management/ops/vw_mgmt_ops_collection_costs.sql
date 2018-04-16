drop view if exists unit_economics.vw_mgmt_ops_collection_costs;
create or replace view unit_economics.vw_mgmt_ops_collection_costs as
with cdre_collection as (
    select
      dre_value,
      dre_date
    from unit_economics.vw_base_dre_costs
    where dre_category = 'Collection'
),
qt_nulls as (
  select
    property_id,
    dt,
    sum(qt) as qt
  from unit_economics.base_ticket_task
  where property_id = -1
    and group_name = 'Collection'
  group by property_id, dt
),
calculated_qt as (
  select
    property_id,
    dt,
    qt,
    avg(qt) over() as _avg
  from unit_economics.base_ticket_task
  where group_name = 'Collection'
    and property_id != -1
),
series as (
	select
		null::double precision as dre_value,
		generate_series((max(dre.dre_date) + interval '1 month')::date,
		    (max(dre.dre_date) + interval '60 month')::date, interval '1 month') as dre_date
	from cdre_collection dre
	union
	select dre_value, dre_date
	from cdre_collection
),
cdre_collection_fc as (
  select
    gap_fill(dre_value) over (order by dre_date) as dre_value,
    dre_date
  from series
),
rent_delay as (
  select distinct
   contract_id,
   tenant_due_date,
   tenant_paid_date,
   date_part('day', cast(tenant_paid_date as timestamp) - cast(tenant_due_date as timestamp)) as rent_delayed_days
   from invoice.report
  where trim("from") = 'Inquilino'
   and trim(item) = 'Aluguel'
   and tenant_due_date is not null
   and tenant_paid_date is not null
),
filtered_contracts as (
    select distinct
      c.property_id as property_id,
      ccs.dre_date as dt_cash_flow
    from unit_economics.vw_base_contract_costs c
    join cdre_collection_fc ccs
      on ccs.dre_date between date_trunc('month', c.init_date) + interval '1 month'
                        and date_trunc('month', coalesce(c.termination_date, c.expected_end_date)) + interval '1 month'
    left join rent_delay rd
      on c.id = rd.contract_id
        and (rd.rent_delayed_days > 0
            or tenant_paid_date is null)
    where ccs.dre_date >= '2016-01-01'
),
ratio as (
  select distinct
    fc.dt_cash_flow,
    qn.qt / count(fc.property_id) over (partition by (fc.dt_cash_flow - interval '1 month')::date) as qt
  from filtered_contracts fc
  left join qt_nulls qn
    on (fc.dt_cash_flow - interval '1 month')::date = qn.dt
),
gen_contracts as (
	select distinct
		fc.property_id,
		fc.dt_cash_flow,
		r.qt as qt,
		avg(r.qt) over () as _avg
	from filtered_contracts fc
  left join ratio r
  	on fc.dt_cash_flow = r.dt_cash_flow
),
calculated as (
  select distinct
    property_id,
    dt,
    qt,
    avg(qt) over (partition by property_id) as _avg
  from calculated_qt
),
spec_gen_prev as (
  select
    coalesce(cc.property_id, gc.property_id) as property_id,
    coalesce((cc.dt + interval '1 month')::date, gc.dt_cash_flow) as dt_cash_flow,
    coalesce(cc.qt, 0) + coalesce(gc.qt, 0) as qt,
    coalesce(gc._avg, 0) + coalesce((gap_fill(cc._avg) over (partition by gc.property_id order by (gc.dt_cash_flow - interval '1 month')::date)), 0) as _avg
  from calculated cc
  full outer join gen_contracts gc
    on cc.property_id = gc.property_id
        and gc.dt_cash_flow::date = (cc.dt + interval '1 month')::date
),
spec_gen as (
	select distinct
		property_id,
		dt_cash_flow,
		case
		    when qt = 0
		        then coalesce(_avg, 0)
		    else coalesce(qt, _avg)
		end as qt,
		case
		    when qt = 0 and _avg is not null
		        then 1
		    else 0
		end as flg_expected_collection
	from spec_gen_prev
),
tt_costs as (
    select distinct
      eg.property_id,
      co.dre_date as dt_cash_flow,
      co.dre_value * eg.qt / case
      												when sum(eg.qt) over (partition by co.dre_date) = 0
      													then null
      												else sum(eg.qt) over (partition by co.dre_date)::double precision
      											 end as vl_collection,
      flg_expected_collection
    from spec_gen eg
    join cdre_collection_fc co
      on co.dre_date = eg.dt_cash_flow
),
contract_costs as (
    select distinct
      fc.property_id,
      co.dre_date as dt_cash_flow,
      (co.dre_value / (count(fc.property_id) over (partition by (co.dre_date - interval '1 month')::date))::double precision) as vl_collection
    from filtered_contracts fc
    join cdre_collection co
      on co.dre_date = fc.dt_cash_flow
),
full_costs as (
  select distinct
    coalesce(tt.property_id, cc.property_id) as property_id,
    coalesce(tt.dt_cash_flow, cc.dt_cash_flow) as dt_cash_flow,
    coalesce(tt.vl_collection, cc.vl_collection) as vl_collection,
    coalesce(tt.flg_expected_collection, 0) as flg_expected_collection
  from tt_costs tt
  full outer join contract_costs cc
    on tt.property_id = cc.property_id
      and tt.dt_cash_flow = cc.dt_cash_flow
)
select distinct
  coalesce(vbpc.sk_property, (fc.property_id || '001')::bigint) as sk_property,
  fc.property_id,
  fc.dt_cash_flow::date,
  fc.vl_collection,
  flg_expected_collection
from full_costs fc
left join unit_economics.vw_base_property_costs vbpc
  on vbpc.property_id = fc.property_id
    and fc.dt_cash_flow - interval '1 month' between date_trunc('month', vbpc.min_version_time) and date_trunc('month', vbpc.max_version_time)
;
