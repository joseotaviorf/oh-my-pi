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
  from unit_economics.vw_base_ticket_task
  where property_id = -1
    and group_name = 'Back-Office (onboarding)'
  group by property_id, dt
),
calculated_qt as (
  select
    tt.property_id,
    tt.dt,
    tt.qt
  from unit_economics.vw_base_ticket_task tt
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
		property_id,
		dre_date as dt
	from
		filtered_contracts_prev fc
	join
		cdre_onboarding dre
		on dre_date between date_trunc('month', fc."from")  + interval '1 month'
                        and date_trunc('month', fc."to") + interval '1 month'
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
      co.dre_value * eg.qt / (sum(eg.qt) over (partition by co.dre_date))::double precision as vl_bo_onboarding
    from espec_gen eg
    join cdre_onboarding co
      on co.dre_date = eg.dt + interval '1 month'
),
contract_costs as (
    select
    	fc.dt,
      fc.property_id,
      co.dre_date as dt_cash_flow,
      co.dre_value / (count(fc.property_id) over (partition by co.dre_date))::double precision as vl_bo_onboarding
    from filtered_contracts fc
    join cdre_onboarding co
      on co.dre_date = fc.dt + interval '1 month'
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
)
select
  coalesce(vbpc.sk_property, (c.property_id || '001')::bigint )as sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_bo_onboarding
from full_costs c
left join unit_economics.vw_base_property_costs vbpc
  on vbpc.property_id = c.property_id
    and c.dt >= vbpc.min_version_time
    and c.dt <= vbpc.max_version_time
;