with month_days as (
	select
		distinct sk_date,
		date_format(cast(date as date), '%Y-%m') as ym,
		count("date") over (partition by year, month) qtd_days
	from datalake_clean.ods_dim_date
	where sk_date != '-1'
)
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
  cast(dd.sk_date as bigint) as sk_cost_date,
  cast(replace(cost, ',', '.') as decimal(14,2)) / dd.qtd_days as cost,
  current_timestamp as ts_load
FROM datalake_clean.marketing_classifieds_costs
left join month_days dd
	on date_format(cast(dt_created as date), '%Y-%m') = dd.ym
WHERE dt_created  = '{date}' and acc = '{account}'
and dd.sk_date != '-1'