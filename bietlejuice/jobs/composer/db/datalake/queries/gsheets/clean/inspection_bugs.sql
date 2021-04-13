SELECT
    INT(NULLIF(id_vistoria, '')) AS id_inspection,
    INT(NULLIF(id_imovel, '')) AS id_house,
    INT(NULLIF(id_vistoriador, '')) AS id_inspector,
    NULLIF(tipo, '') AS type,
    NULLIF(descricao, '') AS description,
    NULLIF(vistoriador, '') AS inspector_name,
    BOOLEAN(NULLIF(solved, '')) AS is_solved,
    DATE(NULLIF(vigencia, '')) AS dt_entrace
FROM
    datalake_gsheets_raw.vistoria_bugs