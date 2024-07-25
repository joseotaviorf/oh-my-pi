WITH filtered_max_stitch_data AS (
    SELECT
        t.*,
        CAST(GET_JSON_OBJECT(t.via, '$.channel') AS STRING) AS ticket_via
    FROM
        datalake_velo_zendesk_homolog_clean.tickets_history t
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_ticket ORDER BY ts_updated DESC) = 1
)
SELECT
    id_assignee,
    id_brand,
    ids_collaborator,
    id_group,
    id_requester,
    id_submitter,
    id_ticket,
    id_ticket_form,
    allow_channelback,
    custom_fields,
    description,
    priority,
    raw_subject,
    recipient,
    satisfaction_rating,
    status,
    subject,
    tags,
    ticket_via,
    type,
    url_ticket,
    via,
    has_incidents,
    is_public,
    dt_extracted,
    ts_created,
    ts_created_local,
    ts_updated,
    NOW() AS ts_load,
    YEAR(ts_created) AS year,
    MONTH(ts_created) AS month,
    DAY(ts_created) AS day
FROM
    filtered_max_stitch_data
WHERE
    ticket_via IS NOT NULL AND raw_subject != 'scrubbed'
