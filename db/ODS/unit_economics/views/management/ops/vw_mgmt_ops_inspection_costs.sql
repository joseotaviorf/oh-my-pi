drop view if exists unit_economics.vw_mgmt_ops_inspection_costs;
create or replace view unit_economics.vw_mgmt_ops_inspection_costs as
with cdre_inspections as (
    select
      dre_value,
      dre_date
    from unit_economics.vw_base_dre_costs
    where dre_category = 'Inspections'
),
init_contract_costs as (
    select distinct
      property_id,
      id,
      date_trunc('month', signature_date)::date as dt
    from unit_economics.vw_base_contract_costs
    where signature_date is not null
),
end_contract_costs as (
   select distinct
      property_id,
      id,
      date_trunc('month', coalesce(termination_date, expected_end_date))::date as dt
    from unit_economics.vw_base_contract_costs
    where termination_date is not null
          or expected_end_date is not null
),
filtered_contracts as (
	select
		property_id,
    id,
		dt
	from
		init_contract_costs
	union
	select
		property_id,
    id,
		dt
	from
		end_contract_costs
),
contract_costs as (
	select
	  fc.property_id,
	  fc.dt,
	  coalesce(ci.dre_date, fc.dt) as dt_cash_flow,
	  ci.dre_value / (count(fc.property_id) over (partition by ci.dre_date))::double precision as vl_inspections,
	  (dre_value is null)::int as flg_expected_inspection
	from filtered_contracts fc
	left join cdre_inspections ci
	  on ci.dre_date = (fc.dt - interval '1 month')::date
),
last_3_avg as (
	select
		t1.dt,
		t1.property_id,
		t1.dt_cash_flow,
		t1.vl_inspections,
		t1.flg_expected_inspection,
		avg(t2.vl_inspections) as m_avg
	from contract_costs t1
	join
		contract_costs t2
		on t2.dt_cash_flow >= t1.dt_cash_flow - interval '3 month' and t2.dt_cash_flow <= t1.dt_cash_flow
	group by t1.dt, t1.property_id, t1.dt_cash_flow, t1.vl_inspections, t1.flg_expected_inspection
),
coalesced_values as (
	select
		coalesce(vbpc.sk_property, (lavg.property_id || '001')::bigint) as sk_property,
		lavg.property_id,
		lavg.dt_cash_flow::date,
		case
			when dt_cash_flow >= '2017-01-01'
			then coalesce(vl_inspections,max(m_avg) filter (where flg_expected_inspection = 0) over ())
			else coalesce(vl_inspections, 0)
		end as vl_inspections,
		flg_expected_inspection
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
	vl_inspections != 0
;