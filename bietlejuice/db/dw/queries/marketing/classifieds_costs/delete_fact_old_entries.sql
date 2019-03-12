delete from marketing.fact_daily_classifieds_costs
where sk_classified in (
    select sk_classified
    from staging.fact_daily_classifieds_costs
    where sk_cost_date = '__PARTITION_DATE__'
) and sk_cost_date = '__PARTITION_DATE__'