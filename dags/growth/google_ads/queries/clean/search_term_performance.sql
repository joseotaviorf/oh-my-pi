SELECT
    BIGINT(adGroup.id) AS id_adgroup,
    BIGINT(campaign.id) AS id_campaign,
    BIGINT(customer.id) AS id_external_customer,
    adGroup.name AS adgroup_name,
    campaign.name AS campaign_name,
    searchTermView.searchTerm AS search_term,
    searchTermView.status AS search_term_status,
    segments.adNetworkType AS ad_network_type,
    segments.device AS device,
    segments.keyword.info.text AS keyword_info_text,
    customer.descriptiveName AS account_descriptive_name,
    account_snake_case,
    report_type,
    metrics.clicks AS clicks,
    DOUBLE(metrics.costMicros)/1000 AS cost,
    metrics.impressions	AS impressions,
    INT(metrics.conversions) AS conversions,
    metrics.interactions AS interactions,
    metrics.interactionEventTypes interaction_event_types,
    DATE(segments.date) AS dt_loaded,
    DATE(dt_created) AS dt_created
FROM
    datalake_google_ads_raw.search_term_performance
WHERE
    DATE(dt_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')