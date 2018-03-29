drop view if exists unit_economics.vw_net_revenue_revenues_brokerage_fee;
---
--- Returns vl_brokerage_fee revenue for each invoice
--- Revenue: Brokerage Fee on rented properties
--- Cash Flow Date: Date of Landlord Payment
---
create or replace view unit_economics.vw_net_revenue_revenues_brokerage_fee as
with base_contract as (
select
	vbpc.sk_property,
	vbpc.property_id,
	vbcc.id as contract_id,
	vbcc.init_date,
	vbcc.rent_value as vl_rent_value,
	coalesce(vbcc.termination_date, vbcc.expected_end_date)::date as end_date
from
	unit_economics.vw_base_contract_costs vbcc
left join
	unit_economics.vw_base_property_costs vbpc
	on vbcc.property_id = vbpc.property_id
	and coalesce(vbcc.termination_date, vbcc.expected_end_date)::date between vbpc.min_version_time
	                                                                    and (vbpc.max_version_time + interval '1 day')
where (vbcc.termination_date is not null
  or vbcc.expected_end_date is not null)
  and vbcc.status in ('Ativo', 'Finalizado')
),
brokerage_fill as (
	select distinct
		sk_property,
		property_id,
		bc.contract_id,
		bc.vl_rent_value,
		case
			when i.contract_id is not null
				then amount::decimal(14,4)
			when bc.init_date >= '2017-01-01'
				then bc.vl_rent_value
			else 0
		end as vl_brokerage_fee,
		init_date,
		i.landlord_status,
		greatest(
			landlord_due_date,
			due_date,
			landlord_paid_date,
			init_date + interval '1 month'
		)::date as dt_cash_flow
	from
		base_contract bc
	left join
		invoice.report i
		on bc.contract_id = i.contract_id
	and
		item = 'TaxaCorretagem'
	and
		"from" = 'Proprietario'
	and
		"to" = 'Contrato'
)
select
	sk_property,
	property_id,
	vl_brokerage_fee,
	vl_rent_value,
	dt_cash_flow,
	0 as flg_expected_brokerage_fee
from
	brokerage_fill
where vl_brokerage_fee != 0
;