WITH stitch_data AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY id, dt ORDER BY updated_at DESC) AS last_updated
    FROM
        datalake_zendesk_tickets_raw.ticket_fields
    WHERE
        dt = '{year}-{month}-{day}'
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
    YEAR(CAST(dt AS DATE)) AS year,
    MONTH(CAST(dt AS DATE)) AS month,
    DAY(CAST(dt AS DATE)) AS day
FROM
    stitch_data
WHERE
    last_updated = 1
