SELECT
    fact_cost AS media_fact_table_name,
    schema,
    table_dim AS media_dim_table_name,
    account_name,
    report_type,
    ad_type,
    campaign_origin_aquisition AS campaign_origin_acquisition,
    origin,
    split_into_cities,
    side,
    mkt_category,
    mkt_flow,
    mkt_completion,
    mkt_origin,
    mkt_channel,
    mkt_medium,
    mkt_source,
    CAST(cost_factor AS FLOAT) AS cost_factor
FROM
    datalake_gsheets_raw.marketing_costs_full_taxonomy