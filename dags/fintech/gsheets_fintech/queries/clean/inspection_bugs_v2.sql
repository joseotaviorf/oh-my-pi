SELECT
    INT(NULLIF(id_inspection, '')) AS id_inspection,
    INT(NULLIF(id_house, '')) AS id_house,
    INT(NULLIF(id_inspector, '')) AS id_inspector,
    NULLIF(type, '') AS type,
    NULLIF(description, '') AS description,
    NULLIF(inspector_name, '') AS inspector_name
FROM
    datalake_gsheets_raw.vistoria_bugs_v2