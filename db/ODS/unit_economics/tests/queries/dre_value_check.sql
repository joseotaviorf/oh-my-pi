with cte_equal as (
	select distinct
		tbl.dt_cash_flow,
		sum(tbl.{_column_value}) over (partition by tbl.dt_cash_flow)::numeric(14,4) as _sum,
		dre."Value"::numeric(14,4),
		sum(tbl.{_column_value}) over (partition by tbl.dt_cash_flow)::numeric(14,4) not between (dre."Value"-100)::numeric(14,4)
																																									and (dre."Value"+100)::numeric(14,4) as _diff
	from unit_economics.{_table} tbl
	join files.costs_dre dre
		on tbl.dt_cash_flow::date = dre."Month"::date
			and dre."Category" = '{dre_category}'
)
select distinct true
from cte_equal
where _diff is true
;
