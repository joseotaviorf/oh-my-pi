drop view if exists unit_economics.vw_mgmt_ops_bo_offboarding_costs;
create or replace view unit_economics.vw_mgmt_ops_bo_offboarding_costs as
with cdre_offboarding as (
    select
      dre_value,
      dre_date
    from unit_economics.vw_base_dre_costs
    where dre_category = 'Back-Office (offboarding)'
),
filtered_contracts as (
    select distinct
      property_id,
      id,
      date_trunc('month', coalesce(termination_date, expected_end_date)::date) as dt
    from unit_economics.vw_base_contract_costs
    where termination_date is not null
          or expected_end_date is not null
),
qt_nulls as (
  select
    property_id,
    dt,
    sum(qt) as qt
  from unit_economics.base_ticket_task
  where property_id = -1
    and group_name = 'Back-Office (offboarding)'
  group by property_id, dt
),
calculated_qt as (
  select
    tt.property_id,
    tt.dt,
    tt.qt
  from unit_economics.base_ticket_task tt
  where tt.group_name = 'Back-Office (offboarding)'
    and property_id != -1
),
ratio as (
  select distinct
    fc.dt,
    qn.qt / count(fc.property_id) over (partition by fc.dt) as qt
  from filtered_contracts fc
  left join qt_nulls qn
    on fc.dt = qn.dt
),
gen_contracts as (
	select
		fc.property_id,
		fc.dt,
		r.qt as qt_gen
	from
  	filtered_contracts fc
  left join ratio r
  	on fc.dt = r.dt
),
espec_gen_prev as (
  select
    fc.property_id,
    cqt.dt as dt,
    cqt.qt as qt
  from
  	filtered_contracts fc
  join calculated_qt cqt
    on cqt.property_id = fc.property_id
  union
  select
  	*
	from gen_contracts
),
espec_gen as (
	select
		property_id,
		dt,
		sum(qt) as qt
	from espec_gen_prev
	group by
		property_id, dt
),
tt_costs as (
    select
      eg.property_id,
      eg.dt,
      co.dre_date as dt_cash_flow,
      case
        when sum(eg.qt) over (partition by co.dre_date) > 0
        then coalesce(co.dre_value * eg.qt / (sum(eg.qt) over (partition by co.dre_date)), 0)::double precision
        else co.dre_value * eg.qt / (sum(eg.qt) over (partition by co.dre_date))::double precision
      end as vl_bo_offboarding,
      (dre_value is null)::int as flg_expected
    from espec_gen eg
    join cdre_offboarding co
      on co.dre_date = (eg.dt + interval '1 month')::date
),
contract_costs as (
    select
      fc.property_id,
      fc.dt,
      co.dre_date as dt_cash_flow,
      co.dre_value / (count(fc.property_id) over (partition by co.dre_date))::double precision as vl_bo_offboarding,
      (dre_value is null)::int as flg_expected
    from filtered_contracts fc
    join cdre_offboarding co
      on co.dre_date = (fc.dt + interval '1 month')::date
),
full_costs as (
  select distinct
    coalesce(tt.property_id, cc.property_id) as property_id,
    coalesce(tt.dt, cc.dt) as dt,
    coalesce(tt.dt_cash_flow, cc.dt_cash_flow) as dt_cash_flow,
    coalesce(tt.vl_bo_offboarding, cc.vl_bo_offboarding) as vl_bo_offboarding,
  	coalesce(tt.flg_expected, cc.flg_expected) as flg_expected
  from tt_costs tt
  full outer join contract_costs cc
    on tt.dt_cash_flow = cc.dt_cash_flow
    and tt.property_id = cc.property_id
),
last_3_avg as (
	select
		t1.dt,
		t1.property_id,
		t1.dt_cash_flow,
		t1.vl_bo_offboarding,
		t1.flg_expected,
		avg(t2.vl_bo_offboarding) as m_avg
	from full_costs t1
	join
		full_costs t2
		on t2.dt_cash_flow >= t1.dt_cash_flow - interval '3 month' and t2.dt_cash_flow <= t1.dt_cash_flow
	group by t1.dt, t1.property_id, t1.dt_cash_flow, t1.vl_bo_offboarding, t1.flg_expected
),
coalesced_values as (
	select
		coalesce(vbpc.sk_house_listing, (lavg.property_id || '001')::bigint) as sk_house_listing,
		lavg.property_id,
		lavg.dt_cash_flow::date,
		case
			when dt_cash_flow >= '2017-01-01'
			then coalesce(vl_bo_offboarding,max(m_avg) filter (where flg_expected = 0) over ())
			else coalesce(vl_bo_offboarding, 0)
		end as vl_bo_offboarding,
		flg_expected
	from last_3_avg lavg
	left join unit_economics.vw_base_property_costs vbpc
	  on vbpc.property_id = lavg.property_id
	    and lavg.dt between vbpc.min_version_time and vbpc.max_version_time
)
select
	*
from
	coalesced_values
where
	vl_bo_offboarding != 0
;