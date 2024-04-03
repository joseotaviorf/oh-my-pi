SELECT DISTINCT
    id AS id_ticket,
    assignee_id AS id_assignee,
    brand_id AS id_brand,
    collaborator_ids AS ids_collaborator,
    group_id AS id_group,
    requester_id AS id_requester,
    submitter_id AS id_submitter,
    ticket_form_id AS id_ticket_form,
    custom_fields,
    description,
    priority,
    raw_subject,
    recipient,
    satisfaction_rating,
    subject,
    status,
    tags,
    type,
    url AS url_ticket,
    via,
    CAST(GET_JSON_OBJECT(via, '$.channel') AS STRING) AS via_channel,
    allow_channelback,
    has_incidents,
    is_public,
    CAST(dt AS DATE) AS dt_extracted,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    YEAR(CAST(dt AS DATE)) AS year,
    MONTH(CAST(dt AS DATE)) AS month,
    DAY(CAST(dt AS DATE)) AS day
FROM
    datalake_zendesk_raw.tickets
WHERE
    dt IN (CAST("{year}-{month}-{day}" AS DATE), CAST("{year}-{month}-{day}" AS DATE) + INTERVAL 1 DAY)
    AND updated_at >= TIMESTAMP(CAST("{year}-{month}-{day}" AS DATE)) + INTERVAL 3 HOUR
    AND updated_at < TIMESTAMP(CAST("{year}-{month}-{day}" AS DATE) + INTERVAL 1 DAY) + INTERVAL 3 HOUR
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_ticket, ts_updated ORDER BY dt_extracted DESC) = 1
