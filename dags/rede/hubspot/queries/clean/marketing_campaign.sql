SELECT
    id::BIGINT AS id_marketing_campaign,
    appId::INT AS id_app,
    contentId::BIGINT AS id_content,
    appName AS app_name,
    subject,
    name,
    type,
    FROM_JSON(counters, 'map<string, int>') AS counters
FROM
    datalake_hubspot_raw.marketing_campaign
