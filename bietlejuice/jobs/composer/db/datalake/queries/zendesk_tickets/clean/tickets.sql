WITH stitch_data AS (
    SELECT
        *,
        CAST(GET_JSON_OBJECT(via, '$.channel') AS STRING) AS ticket_via,
        ROW_NUMBER() OVER (PARTITION BY id, dt ORDER BY updated_at DESC) AS last_updated
    FROM
        datalake_zendesk_tickets_raw.tickets
    WHERE
        CAST(GET_JSON_OBJECT(via, '$.channel') AS STRING) IS NOT NULL
        AND raw_subject != 'scrubbed'
        AND dt = '{year}-{month}-{day}'
)
SELECT
    id AS id_ticket,
    satisfaction_rating,
    url AS url_ticket,
    priority,
    raw_subject,
    subject,
    ticket_via,
    via,
    tags,
    group_id AS id_group,
    ticket_form_id AS id_ticket_form,
    requester_id AS id_requester,
    assignee_id AS id_assignee,
    collaborator_ids AS ids_collaborator,
    brand_id AS id_brand,
    submitter_id AS id_submitter,
    status,
    custom_fields,
    has_incidents,
    type,
    allow_channelback,
    description,
    recipient,
    is_public,
    dt AS dt_extracted,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    FROM_UTC_TIMESTAMP(CAST(created_at AS TIMESTAMP), 'Brazil/East') AS ts_created_local,
    CAST(GREATEST(created_at,updated_at) AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    YEAR(CAST(dt AS DATE)) AS year,
    MONTH(CAST(dt AS DATE)) AS month,
    DAY(CAST(dt AS DATE)) AS day
FROM
    stitch_data
WHERE
    last_updated = 1
