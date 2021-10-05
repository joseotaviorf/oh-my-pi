SELECT
    campaign_id AS id_campaign,
    `name` AS campaign_name,
    description AS campaign_description,
    schedule_type,
    tags,
    channels,
    conversion_behaviors,
    messages,
    archived,
    draft,
    TO_TIMESTAMP(last_sent) AS ts_last_sent,
    TO_TIMESTAMP(first_sent) AS ts_first_sent,
    TO_TIMESTAMP(created_at) AS ts_created,
    TO_TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_braze_details_raw.campaign_details_indica_ai