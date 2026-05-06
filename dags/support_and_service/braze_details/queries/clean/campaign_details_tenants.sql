SELECT
    campaign_id AS id_campaign,
    `name` AS campaign_name,
    description AS campaign_description,
    CASE
        WHEN `name` LIKE '%MX%' THEN 'MX'
        WHEN `name` IS NULL THEN 'Undefined'
        ELSE 'BR'
    END AS country_code,
    schedule_type,
    FROM_JSON(tags, 'array<string>') AS tags,
    REGEXP_EXTRACT(tags, 'journeyStep=(\\w+)') AS journey_step,
    FROM_JSON(channels, 'array<string>') AS channels,
    FROM_JSON(REPLACE(conversion_behaviors, 'None', '\'\''), 'array<map<string,string>>') AS conversion_behaviors,
    messages,
    archived,
    draft,
    TO_TIMESTAMP(last_sent) AS ts_last_sent,
    TO_TIMESTAMP(first_sent) AS ts_first_sent,
    TO_TIMESTAMP(created_at) AS ts_created,
    TO_TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_braze_details_raw.campaign_details_tenants
