SELECT
    NULLIF(fact_cost, '') AS media_fact_table_name,
    NULLIF(schema, '') AS schema,
    NULLIF(table_dim, '') AS media_dim_table_name,
    NULLIF(account_name, '') AS account_name,
    NULLIF(report_type, '') AS report_type,
    NULLIF(ad_type, '') AS ad_type,
    NULLIF(campaign_origin_aquisition, '') AS campaign_origin_acquisition,
    NULLIF(origin, '') AS origin,
    NULLIF(split_into_cities, '') AS split_into_cities,
    NULLIF(side, '') AS side,
    NULLIF(mkt_category, '') AS mkt_category,
    NULLIF(mkt_flow, '') AS mkt_flow,
    NULLIF(mkt_completion, '') AS mkt_completion,
    NULLIF(mkt_origin, '') AS mkt_origin,
    NULLIF(mkt_channel, '') AS mkt_channel,
    NULLIF(mkt_medium, '') AS mkt_medium,
    NULLIF(mkt_source, '') AS mkt_source,
    NULLIF(cost_factor, '') AS cost_factor
FROM
    datalake_gsheets_raw.marketing_costs_full_taxonomy