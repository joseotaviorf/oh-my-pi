drop view if exists unit_economics.vw_mgmt_ops_bo_onboarding_costs;
create or replace view unit_economics.vw_mgmt_ops_bo_onboarding_costs as
with cdre_onboarding as (
    select
      dre_value,
      dre_date
    from unit_economics.vw_base_dre_costs
    where dre_category = 'Back-Office (onboarding)'
),
qt_nulls as (
  select
    property_id,
    dt,
    sum(qt) as qt
  from unit_economics.base_ticket_task
  where property_id = -1
    and group_name = 'Back-Office (onboarding)'
  group by property_id, dt
),
calculated_qt as (
  select
    tt.property_id,
    tt.dt,
    tt.qt
  from unit_economics.base_ticket_task tt
  where tt.group_name = 'Back-Office (onboarding)'
    and property_id != -1
),
filtered_contracts_prev as (
  select distinct
    property_id,
    case
      when signature_date::date > init_date::date
        then init_date::date
      else signature_date::date
    end as "from",
    case
      when signature_date::date > init_date::date
        then signature_date::date
      else init_date::date
    end as "to"
  from unit_economics.vw_base_contract_costs
  where signature_date is not null
    and init_date is not null
),
filtered_contracts as(
	select distinct
		fc.property_id,
		coalesce(dre.dre_date, date_trunc('month', fc."to") + interval '1 month') as dt
	from filtered_contracts_prev fc
	left join cdre_onboarding dre
		on dre.dre_date between date_trunc('month', fc."from") + interval '1 month'
                        and date_trunc('month', fc."to") + interval '1 month'
    where fc."from" >= '2015-12-01'
        and fc."to" >= '2015-12-01'
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
    coalesce(cqt.dt, fc.dt) as dt,
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
      (eg.dt - interval '1 month')::date as dt_cash_flow,
      case
        when sum(eg.qt) over (partition by eg.dt) > 0
        then coalesce(co.dre_value * eg.qt / (sum(eg.qt) over (partition by eg.dt)), 0)::double precision
        else co.dre_value * eg.qt / (sum(eg.qt) over (partition by eg.dt))::double precision
      end as vl_bo_onboarding
    from espec_gen eg
    left join cdre_onboarding co
      on co.dre_date = (eg.dt - interval '1 month')::date
),
contract_costs as (
    select
      fc.dt,
      fc.property_id,
      (fc.dt - interval '1 month')::date as dt_cash_flow,
      co.dre_value / (count(fc.property_id) over (partition by fc.dt))::double precision as vl_bo_onboarding
    from filtered_contracts fc
    left join cdre_onboarding co
      on co.dre_date = (fc.dt - interval '1 month')::date
),
full_costs as (
  select distinct
    coalesce(tt.property_id, cc.property_id) as property_id,
    coalesce(tt.dt, cc.dt) as dt,
    coalesce(tt.dt_cash_flow, cc.dt_cash_flow) as dt_cash_flow,
    coalesce(tt.vl_bo_onboarding, cc.vl_bo_onboarding) as vl_bo_onboarding
  from tt_costs tt
  full outer join contract_costs cc
    on tt.dt_cash_flow = cc.dt_cash_flow
    	and tt.property_id = cc.property_id
),
result as (
    select
      coalesce(vbpc.sk_property, (c.property_id || '001')::bigint) as sk_property,
      c.property_id,
      c.dt_cash_flow::date,
      c.vl_bo_onboarding,
      (c.vl_bo_onboarding is null)::int as flg_expected_bo_onboarding
    from full_costs c
    left join unit_economics.vw_base_property_costs vbpc
      on vbpc.property_id = c.property_id
        and c.dt >= vbpc.min_version_time
        and c.dt <= vbpc.max_version_time
),
m_avg_prev as (
    select distinct
        dt_cash_flow,
        avg(vl_bo_onboarding) over (partition by dt_cash_flow order by dt_cash_flow) as _avg1
    from result
    order by dt_cash_flow asc
),
last_value as (
    select
        dt_cash_flow,
        case
            when _avg1 is null
                and avg(_avg1) over (rows between 3 preceding and 1 preceding) is not null
                and lag(_avg1) over () is not null
                and lead(_avg1) over () is null
              then avg(_avg1) over (rows between 3 preceding and 1 preceding)
            else _avg1
        end as m_avg
    from m_avg_prev
),
last_value_gap_fill as (
    select
        dt_cash_flow,
        coalesce(m_avg, gap_fill(m_avg) over ()) as new_value
    from last_value
)
select
    r.sk_property,
    r.property_id,
    r.dt_cash_flow,
    r.flg_expected_bo_onboarding,
    lv.new_value as vl_bo_onboarding
from result r
join last_value_gap_fill lv
    on r.dt_cash_flow = lv.dt_cash_flow
;