with cte_equal as (
	select distinct
		f.sk_cash_flow_date,
		sum(f.{_column_value}) over (partition by f.sk_cash_flow_date)::numeric(14,1) as _sum,
		dre."Value"::numeric(14,1),
		sum(f.{_column_value}) over (partition by f.sk_cash_flow_date)::numeric(14,1) not between (dre."Value"-500)::numeric(14,1)
																																									and (dre."Value"+500)::numeric(14,1) as _diff
	from unit_economics.fact_property_economics f
	join files.costs_dre dre
		on f.sk_cash_flow_date = to_char(dre."Month", 'YYYYMMDD')::int
			and dre."Category" = '{dre_category}'
)
select distinct false
from cte_equal
where _diff is true
;