SELECT
    id AS id_ticket_field,
    title,
    description,
    agent_description,
    url
    raw_title,
    raw_title_in_portal,
    raw_description,
    custom_field_options,
    type,
    removable AS is_removable,
    position AS is_position,
    required AS is_required,
    active AS is_active,
    collapsed_for_agents AS is_collapsed_for_agents,
    visible_in_portal AS is_visible_in_portal,
    required_in_portal AS is_required_in_portal,
    editable_in_portal AS is_editable_in_portal,
    title_in_portal AS is_title_in_portal,
    dt AS dt_extracted,
    created_at AS ts_created,
    updated_at AS ts_updated,
    NOW() AS ts_load,
    YEAR(dt) AS year,
    MONTH(dt) AS month,
    DAY(dt) AS day
FROM
    datalake_zendesk_tickets_raw.ticket_fields
WHERE
    dt IN (CAST('{year}-{month}-{day}' AS DATE), CAST('{year}-{month}-{day}' AS DATE) + INTERVAL 1 DAY)
