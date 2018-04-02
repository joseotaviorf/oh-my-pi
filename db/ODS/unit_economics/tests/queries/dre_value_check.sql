with cte_equal as (
	select distinct
		f.sk_cash_flow_date,
		sum(f.{_column_value}) over (partition by f.sk_cash_flow_date)::int as calculated_sum,
		dre."Value" as dre_value,
		((dre."Value" / nullif(sum(f.{_column_value}) over (partition by f.sk_cash_flow_date)::float, 0)) - 1)::numeric(14,3) as _percentage,
		abs(((dre."Value" / nullif(sum(f.{_column_value}) over (partition by f.sk_cash_flow_date)::float, 0)) - 1)::numeric(14,3)) >= 0.06 as _diff
	from unit_economics.fact_property_economics f
	join files.costs_dre dre
		on f.sk_cash_flow_date = to_char(dre."Month", 'YYYYMMDD')::int
			and dre."Category" = '{dre_category}'
),
cte_rn as (
	select *, row_number() over (order by sk_cash_flow_date) as rn
	from cte_equal
),
max_rn as (
	select *, max(rn) over () as _max
	from cte_rn
)
select distinct false
from max_rn
where _diff is true
	and rn != _max
;