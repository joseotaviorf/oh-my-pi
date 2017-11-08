drop view vw_net_revenue_revenues_brokerage_fee;
---
--- Returns vl_brokerage_fee revenue for each invoice
--- Revenue: Brokerage Fee on rented properties
--- Cash Flow Date: Date of Landlord Payment
---
create or replace view vw_net_revenue_revenues_brokerage_fee as
with filtered_contracts as (
select distinct
	property_id,
	id,
	coalesce(termination_date, expected_end_date)::date as end_date
from
	vw_base_contract_costs
where termination_date is not null
  or expected_end_date is not null
),
base_contract as (
	select
		base.*,
		c.id as contract_id
	from
		vw_base_property_costs base
	left join
		filtered_contracts c
		on base.property_id = c.property_id
		and c.end_date between base.min_version_time and base.max_version_time
)
select
	sk_property,
	property_id,
	amount::decimal(14,4) as vl_brokerage_fee,
	greatest(
		landlord_due_date,
		due_date,
		landlord_paid_date,
		(concat(
			substring(year_month from 1 for 4),'-',
			substring(year_month from 5 for 6)::int,'-',
			'15'))::date + interval '1 month'
	)::date as dt_cash_flow
from
	base_contract bc
left join
	invoice i
	on bc.contract_id = i.contract_id
where
	item = 'TaxaCorretagem'
and
	landlord_status = 'paid'
and
	"from" = 'Proprietario'
and
	"to" = 'Contrato'
;