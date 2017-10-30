drop view vw_net_revenue_revenues_mgmt_fee;
---
--- Returns vl_management_fee revenue for each invoice
--- Revenue: Management Fee on rented properties
--- Cash Flow Date: Date of Landlord Payment
---
create or replace view vw_net_revenue_revenues_mgmt_fee as
with filtered_contracts as (
select distinct
	imovel_id as property_id,
	id,
	(max(coalesce("dataRescisao", "dataFimContratoPrevisto")) over (partition by imovel_id))::date as end_date
from
	contract
where
	tipo = 'FullService'
	and ("dataRescisao" is not null
	or "dataFimContratoPrevisto" is not null)
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
	amount::decimal(14,4) as vl_management_fee,
	landlord_paid_date as dt_cash_flow
from
	base_contract bc
left join
	invoice i
	on bc.contract_id = i.contract_id
where
	item = 'TaxaAdministracao'
and
	landlord_status = 'paid'
;
