WITH numbered_ticket_history AS (
    SELECT *,
        ROW_NUMBER() OVER(PARTITION BY id_ticket ORDER BY ts_updated DESC) AS rw
    FROM
        datalake_hubspot.ticket_history
)
SELECT
    id_ticket,
    id_stage,
    id_pipeline,
    id_hubspot_owner,
    id_stage_history,
    id_pipeline_history,
    content,
    subject,
    onboarding_type,
    field_sales,
    has_accepted_contact_with_agents,
    is_archived,
    dt_term_signed,
    dt_term_sent,
    dt_documents_received,
    dt_onboarding,
    ts_archived,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    numbered_ticket_history
WHERE
    rw = 1
    AND NOT is_archived