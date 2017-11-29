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
  from unit_economics.vw_base_ticket_task
  where property_id = -1
    and group_name = 'Collection'
  group by property_id, dt
),
calculated_qt as (
  select
    tt.property_id,
    tt.dt,
    tt.qt
  from unit_economics.vw_base_ticket_task tt
  where tt.group_name = 'Collection'
    and property_id != -1
),
rent_delay as (
  select
   contract_id,
   tenant_due_date,
   tenant_paid_date,
   date_part('day', cast(tenant_paid_date as timestamp) - cast(tenant_due_date as timestamp)) as rent_delayed_days
   from invoice
  where trim("from") = 'Inquilino'
   and trim(item) = 'Aluguel'
   and tenant_due_date is not null
   and tenant_paid_date is not null
),
filtered_contracts as (
    select distinct
      c.property_id as property_id,
      date_trunc('month', rd.tenant_due_date)::date as dt
    from unit_economics.vw_base_contract_costs c
    join rent_delay rd
      on c.id = rd.contract_id
    where rd.rent_delayed_days > 0
        or tenant_paid_date is null
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
      co.dre_value * eg.qt / (sum(eg.qt) over (partition by co.dre_date))::double precision as vl_collection
    from espec_gen eg
    join cdre_collection co
      on co.dre_date = eg.dt + interval '1 month'
),
contract_costs as (
    select
      fc.property_id,
      fc.dt,
      co.dre_date as dt_cash_flow,
      co.dre_value / (count(fc.property_id) over (partition by co.dre_date))::double precision as vl_collection
    from filtered_contracts fc
    join cdre_collection co
      on co.dre_date = date_trunc('month', fc.dt) + interval '1 month'
),
full_costs as (
  select distinct
    coalesce(tt.property_id, cc.property_id) as property_id,
    coalesce(tt.dt, cc.dt) as dt,
    coalesce(tt.dt_cash_flow, cc.dt_cash_flow) as dt_cash_flow,
    coalesce(tt.vl_collection, cc.vl_collection) as vl_collection
  from tt_costs tt
  full outer join contract_costs cc
    on tt.dt_cash_flow = cc.dt_cash_flow
)
select
  vbpc.sk_property,
  fc.property_id,
  fc.dt_cash_flow,
  fc.vl_collection
from full_costs fc
join unit_economics.vw_base_property_costs vbpc
  on vbpc.property_id = fc.property_id
    and fc.dt between vbpc.min_version_time and vbpc.max_version_time
;