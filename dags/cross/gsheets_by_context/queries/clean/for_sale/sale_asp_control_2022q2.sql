SELECT
    INT(NULLIF(id_house, '')) AS id_house,
    INT(NULLIF(id_owner, '')) AS id_owner,
    asp_list,
    asp_group,
    DATE(NULLIF(dt_separation, '')) AS dt_separation
FROM
    datalake_gsheets_raw.sale_asp_control_2022q2
