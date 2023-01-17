SELECT
    id_campaign,
    campaign_name,
    campaign_description,
    schedule_type,
    tags,
    channels,
    conversion_behaviors,
    messages,
    archived AS is_archived,
    draft AS is_draft,
    ts_last_sent,
    ts_first_sent,
    ts_created,
    ts_updated,
    YEAR(ts_updated) AS year,
    MONTH(ts_updated) AS month,
    DAY(ts_updated) AS day
FROM
    datalake_braze_details_clean.campaign_details_tenants
WHERE
    DATE(ts_updated) = DATE('{year}-{month}-{day}')
    AND campaign_name LIKE '%MX%'