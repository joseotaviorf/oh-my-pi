drop view if exists unit_economics.vw_liquidity_lockbox_costs;
---
--- Returns vl_lockbox_costs costs for each first version property
--- Cost: Tenant Daily Costs for Google Adwords, Facebook, Criteo and Classifieds
--- Cash Flow Date: Date of Payment ( 1 month after invoice )
---
create or replace view unit_economics.vw_liquidity_lockbox_costs as
with lockbox_dates as (
	select
		imovel_id as property_id,
		min(dt_added)::date as dt_cash_flow
	from
		property_visit_information pvi
	where
		pvi.informacoes_visita = 'CHAVE_CAIXA_QUINTOANDAR'
		and
		coalesce(date_part('days', dt_deleted - dt_added), 0) > 0
	group by imovel_id
)
select
	base.sk_property,
	base.property_id,
	lock.dt_cash_flow,
	56.00 as vl_lockbox
from
	unit_economics.vw_base_property_costs base
left join
	lockbox_dates lock
	on base.property_id = lock.property_id
	and lock.dt_cash_flow >= base.min_version_time and lock.dt_cash_flow < base.max_version_time
where lock.property_id is not null
;