with month_dates as (
    select
		cast(regexp_extract(trim(date), '(\d\d\d\d-\d\d-\d\d)', 1) as date) as dd_date,
		date_trunc('month', cast(regexp_extract(trim(date), '(\d\d\d\d-\d\d-\d\d)', 1) as date)) as dd_month,
	  	count(cast(regexp_extract(trim(date), '(\d\d\d\d-\d\d-\d\d)', 1) as date)) over
	  			(partition by date_trunc('month', cast(regexp_extract(trim(date), '(\d\d\d\d-\d\d-\d\d)', 1) as date))) as total_days
		from datalake_clean.ods_dim_date dd)
SELECT
  cast(CASE source
    WHEN 'Zap Imóveis' THEN 1
    WHEN 'VivaReal' THEN 2
    WHEN 'Mitula' THEN 3
    WHEN 'OLX' THEN 4
    WHEN 'Mercado Livre' THEN 5
    WHEN 'Imovelweb' THEN 6
    WHEN '123i' THEN 7
    ELSE -1
  END as SMALLINT) as sk_classified,
  cast(date_format(month_dates.dd_date, '%Y%m%d') as bigint) as sk_cost_date,
  round((cast(REPLACE(cost, ',', '') as decimal(14,2))/month_dates.total_days),2) as cost,
  current_timestamp as ts_load
FROM datalake_clean.marketing_classifieds_costs mcc
inner join month_dates
on date_trunc('month',cast(mcc.dt_created as date)) = month_dates.dd_month
WHERE dt_created  = '{date}' and acc = '{account}'
