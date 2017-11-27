drop view if exists vw_liquidity_ops_cs_pre_sale_costs;
create or replace view vw_liquidity_ops_cs_pre_sale_costs as
with cdre_cs_pre_sale as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Customer Support (pre-sale)'
),
filtered_properties as (
    select distinct
        sk_property,
        property_id,
        publication_date::date,
        min_version_time::date,
		case
			when min_version_time + interval '1 year' >= max_version_time
				then max_version_time
			when min_version_time + interval '1 year' >= now()
				then now()
			else
				min_version_time + interval '1 year'
		end as max_liquidity_date
    from vw_base_property_costs
    where status = 'publicado'
),
costs as (
    select
      fp.sk_property,
      fp.property_id,
      cps.dre_date as dt_cash_flow,
      cps."value" / (count(fp.property_id) over (partition by cps.dre_date))::double precision as vl_cs_pre_sale
    from filtered_properties fp
    join cdre_cs_pre_sale cps
      on cps.dre_date between date_trunc('month', fp.min_version_time) + interval '1 month'
         and date_trunc('month', fp.max_liquidity_date) + interval '1 month'
)
select
  vbpc.sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_cs_pre_sale
from costs c
join vw_base_property_costs vbpc
  on vbpc.sk_property = c.sk_property
;
