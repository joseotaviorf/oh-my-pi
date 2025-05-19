SELECT
    id AS id_email_event,
    emailCampaignId::BIGINT AS id_email_campaign,
    emailCampaignGroupId::BIGINT AS id_email_campaign_group,
    appId::INT AS id_app,
    portalId::BIGINT AS id_portal,
    smtpId AS id_smtp,
    appName AS app_name,
    recipient,
    type AS event_type,
    FROM_JSON(sentBy, "struct<id: string, created_at:timestamp>") AS sent_by,
    attempt::INT AS attempt_number,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_hubspot_raw.marketing_email_event
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
