WITH dedup_ticket_fields AS (
    SELECT
        *
    FROM
        datalake_zendesk_tickets_raw.ticket_fields
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
)
SELECT
    id AS id_ticket_fields,
    title,
    description,
    agent_description,
    url AS url_ticket_fields,
    raw_title,
    raw_title_in_portal,
    raw_description,
    custom_field_options,
    removable AS is_removable,
    position AS is_position,
    required AS is_required,
    type,
    active AS is_active,
    collapsed_for_agents AS is_collapsed_for_agents,
    visible_in_portal AS is_visible_in_portal,
    required_in_portal AS is_required_in_portal,
    editable_in_portal AS is_editable_in_portal,
    title_in_portal AS is_title_in_portal,
    dt AS dt_extracted,
    CAST(FROM_UTC_TIMESTAMP(created_at, 'Brazil/East') AS TIMESTAMP) AS ts_created_local,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    YEAR(CAST(updated_at AS DATE)) AS year,
    MONTH(CAST(updated_at AS DATE)) AS month,
    DAY(CAST(updated_at AS DATE)) AS day
FROM
    dedup_ticket_fields
