drop view vw_net_revenue_affiliate_commission_costs;
---
--- Returns vl_affiliate_commission costs for each first version property
--- Cost: Affiliate Commission on rented properties
--- Cash Flow Date: Date of Payment
---
create or replace view vw_net_revenue_affiliate_commission_costs as
with affiliate_filtered_base as (
	select
		base.*
	from
		vw_base_property_costs base
	left join
		potential_listings pl
		on pl.property_id = base.property_id
	left join
		lead l
		on pl.lead_id = l.id
	where
		pl.lead_id is not null
		and l.usuario_que_indicou_id is not null
		and l.tipo='Afiliado'
)
select
	base.sk_property,
	property_id,
	payment_date::date as dt_cash_flow,
	valor as vl_affiliate_commission
from
	affiliate_filtered_base base
left join
	affiliate_payments ap
	on ap.imovel_id::integer = base.property_id
where
	base.version = 1
and
	tipo='porcentagemPorIndicacaoDeImovel'
;