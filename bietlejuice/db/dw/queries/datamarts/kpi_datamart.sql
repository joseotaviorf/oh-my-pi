SELECT 
	date_week,
	metric_name,
	metric_value
FROM 

--- Indicador Visits
   (
	SELECT 
		date_table.week_start as date_week,
		'Visits' as metric_name,
		count(1) as metric_value
	FROM public.fact_listing_rent_flows as demand
	left join public.dim_date as date_table
	on demand.sk_visit_date=date_table.sk_date
	
	WHERE
	demand.sk_visit_date IS NOT NULL and date_table.week_start is not null and date_table.week_start >= '2017-01-01'
	GROUP by 1
	order by 1 desc) AS visits

