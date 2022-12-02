WITH filtered_max_stitch_data AS (
    SELECT
        t.*,
        CAST(GET_JSON_OBJECT(t.via, '$.channel') AS STRING) AS ticket_via
    FROM
        datalake_zendesk_tickets_raw.tickets t
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
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
    YEAR(CAST(updated_at AS DATE)) AS year,
    MONTH(CAST(updated_at AS DATE)) AS month,
    DAY(CAST(updated_at AS DATE)) AS day
FROM
    filtered_max_stitch_data
WHERE
    ticket_via IS NOT NULL AND raw_subject != 'scrubbed'
