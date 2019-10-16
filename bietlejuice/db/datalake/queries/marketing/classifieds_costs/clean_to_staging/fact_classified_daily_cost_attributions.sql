with month_days as (
	select
		distinct sk_date,
		date_format(cast(date as date), '%Y%m') as ym,
		count("date") over (partition by year, month) qtd_days
	from datalake_clean.ods_dim_date
	where sk_date != '-1'
),
demand_costs as (
    SELECT
      to_hex(md5(to_utf8(source))) as sk_classified,
      cast(dd.sk_date as bigint) as sk_cost_date,
      'demand' as funnel_side,
      cast(cost as decimal(14,2)) / dd.qtd_days as cost,
      current_timestamp as ts_load
    FROM datalake_clean.marketing_demand_classifieds_costs
    left join month_days dd
        on date_format(cast(dt_created as date), '%Y%m') = dd.ym
    and dd.sk_date != '-1'
),
supply_costs as (
    SELECT
      to_hex(md5(to_utf8(source))) as sk_classified,
      cast(dd.sk_date as bigint) as sk_cost_date,
      'supply' as funnel_side,
      cast(cost as decimal(14,2)) / dd.qtd_days as cost,
      current_timestamp as ts_load
    FROM datalake_clean.marketing_supply_classifieds_costs
    left join month_days dd
        on date_format(cast(dt_created as date), '%Y%m') = dd.ym
    and dd.sk_date != '-1'
),
supply_demand_classifieds_costs as (
    select
        sk_classified,
        sk_cost_date as sk_date,
        funnel_side,
        cost,
        ts_load
    from demand_costs
    union
    select
        sk_classified,
        sk_cost_date,
        funnel_side,
        cost,
        ts_load
    from supply_costs
)
select
    sk_classified,
    sk_date,
    funnel_side,
    cost,
    ts_load
from supply_demand_classifieds_costs