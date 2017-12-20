drop view if exists unit_economics.vw_mgmt_insurance_fee;
---
--- Returns vl_insurance_costs based on contract
--- Costs: Insurance costs for Rented properties
--- Cash Flow Date: 10th of each Contract Month following start and end rule
---
create or replace view unit_economics.vw_mgmt_insurance_fee as
with payed_contracts as (
	select
		distinct
			c.id as contract_id,
			c.status,
			c.init_date as dt_start,
			coalesce(c.termination_date,c.expected_end_date) as dt_end,
			c.property_id as property_id,
			c.rent_value as rent
	from
		unit_economics.vw_base_contract_costs c
),
pay_dates as (
	select
		*,
		case
			when date_part('day', dt_start) > 20
			then (date_trunc('month', dt_start + interval '3 month') + interval '9 day')::date
			else (date_trunc('month', dt_start + interval '2 month') + interval '9 day')::date
		end as dt_first_pay,
		greatest(case
			when date_part('day', dt_start) > 20
			then (date_trunc('month', dt_start + interval '3 month') + interval '9 day')::date
			else (date_trunc('month', dt_start + interval '2 month') + interval '9 day')::date
		end,(date_trunc('month', dt_end + interval '1 month') + interval '9 day')::date) as dt_last_pay
	from
		payed_contracts
),
insurance_dates_prev as (
	select
		pd.contract_id,
		pd.property_id,
		dd."date" as dt_cash_flow,
		dt_start,
		rent,
		row_number() over (partition by pd.contract_id order by dd."date") as rn
	from
		pay_dates pd
	left join
		dim_date dd
		on pd.dt_first_pay <= dd."date"
		and pd.dt_last_pay >= dd."date"
		and date_part('day', pd.dt_first_pay) = date_part('day', dd."date")
	where dd."date" is not null
	and rent is not null
),
insurance_dates as (
	select
		id.contract_id,
		id.property_id,
		id.dt_cash_flow,
		coalesce(
		case
			when (id1.dt_cash_flow < '2017-05-21' or id1.dt_cash_flow is null)
			then id.rent * 0.0725
			else id.rent * 0.045
		end, 0
		) as cardiff_amount,
		case
			when id.dt_cash_flow > now() then 1
			else 0
		end as flg_expected
	from insurance_dates_prev id
		left join insurance_dates_prev id1
		 on id.contract_id = id1.contract_id
		 and id1.rn % 12 = 0 and id.rn/12 = id1.rn/12
)
,
base_contract as (
	select
		base.*,
		c.contract_id
	from
		unit_economics.vw_base_property_costs base
	left join
		payed_contracts c
		on base.property_id = c.property_id
		and c.dt_end between base.min_version_time and base.max_version_time
)
select
	max(sk_property)::bigint as sk_property,
	bc.property_id,
	bc.contract_id,
	cardiff_amount::decimal(14,4) as vl_insurance_fee,
	dt_cash_flow as dt_cash_flow,
	flg_expected
from
	base_contract bc
left join
	insurance_dates i
	on bc.contract_id = i.contract_id
where coalesce(cardiff_amount, 0) > 0
group by
	bc.property_id,
	dt_ash_flow,
	vl_insurance_fee,
	bc.contract_id,
	flg_expected
;c