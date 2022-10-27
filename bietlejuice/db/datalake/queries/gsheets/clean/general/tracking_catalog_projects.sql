SELECT
    NULLIF(STRING(id_app),'') AS id_app,
    NULLIF(STRING(project_name),'') AS project_name,
    NULLIF(STRING(description),'') AS description,
    NULLIF(STRING(owner),'') AS owner,
    NULLIF(STRING(tracking_tool),'') AS tracking_tool,
    NULLIF(STRING(lines),'') AS lines,
    NULLIF(STRING(principal_metrics),'') AS principal_metrics,
    NULLIF(STRING(key_concepts),'') AS key_concepts
FROM
    datalake_gsheets_raw.tracking_catalog_projects
