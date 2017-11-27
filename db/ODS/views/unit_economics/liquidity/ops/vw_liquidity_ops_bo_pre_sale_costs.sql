drop view if exists vw_liquidity_ops_bo_pre_sale_costs;
create or replace view vw_liquidity_ops_bo_pre_sale_costs as
with cdre_bo_pre_sale as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Back-Office (pre-sale)'
),
filtered_contracts as (
    select distinct
      vbpc.sk_property,
      c.property_id,
      c.created_date::date as created_date
    from vw_base_property_costs vbpc
	left join vw_base_contract_costs c
	   on vbpc.property_id = c.property_id
    	and c.created_date between vbpc.min_version_time and vbpc.max_version_time
    where
		created_date is not null
	and -- check for max liquidity date
		c.created_date <=
		(case
			when min_version_time + interval '1 year' >= max_version_time
				then max_version_time
			when min_version_time + interval '1 year' >= now()
				then now()
			else
				min_version_time + interval '1 year'
		end)
),
costs as (
    select
      fc.sk_property,
      fc.property_id,
      fc.created_date,
      cps.dre_date as dt_cash_flow,
      cps."value" / (count(fc.property_id) over (partition by cps.dre_date))::double precision as vl_bo_pre_sale
    from filtered_contracts fc
    join cdre_bo_pre_sale cps
      on cps.dre_date = date_trunc('month', fc.created_date) + interval '1 month'
)
select
  sk_property,
  c.property_id,
  c.dt_cash_flow,
  sum(c.vl_bo_pre_sale) as vl_bo_pre_sale
from costs c
group by c.property_id, c.dt_cash_flow, c.sk_property
;
