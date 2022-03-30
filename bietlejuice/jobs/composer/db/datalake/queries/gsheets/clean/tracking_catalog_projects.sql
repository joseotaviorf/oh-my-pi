SELECT
    NULLIF(STRING(id_app),'') AS id_app,
    NULLIF(STRING(project_name),'') AS project_name,
    NULLIF(STRING(description),'') AS description,
    NULLIF(STRING(owner),'') AS owner
FROM
    datalake_gsheets_raw.tracking_catalog_projects