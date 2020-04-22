/*Share de custos com base no budget do mensal*/

with
share as (
	SELECT DISTINCT
		cast(replace(dd.year_month, '/', '') as integer) as year_month,
		atr.city_group,
	    (sum(budget) over (PARTITION by year_month, city_group)::float
	    /
		sum(budget) over (PARTITION by year_month)::float
		) as share
	FROM
		datalake_raw.gsheets_marketing_affiliates_targets_replanning atr
		join dim_date dd
			on date(atr.date)= dd.date
	),
dim_distinct as (
	select distinct
	 	dd.sk_date,
	 	cast(replace(dd.year_month, '/', '') as integer) as year_month,
	 	dr.city_group
	from
	 	dim_date dd, dim_region dr
	)
select
	d.sk_date,
	d.city_group,
	coalesce(s.share,0) as share
from
	dim_distinct d
	join share s
		on d.year_month=s.year_month
		and d.city_group=s.city_group