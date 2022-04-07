SELECT
    NULLIF(STRING(id_app), '') AS id_app,
    NULLIF(STRING(project_name), '') AS project_name,
    NULLIF(STRING(description), '') AS description,
    NULLIF(STRING(owner), '') AS owner,
    NULLIF(STRING(event_type), '') AS event_type,
    NULLIF(STRING(event_property), '') AS event_property,
    NULLIF(STRING(platform), '') AS platform,
    NULLIF(STRING(type), '') AS type,
    NULLIF(STRING(status), '') AS status,
    NULLIF(STRING(first_seen), '') AS first_seen,
    NULLIF(STRING(last_seen), '') AS last_seen
FROM
    datalake_gsheets_raw.tracking_catalog_event_properties