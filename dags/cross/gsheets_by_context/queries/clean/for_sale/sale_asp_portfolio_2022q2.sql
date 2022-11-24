SELECT
    INT(NULLIF(id_house, '')) AS id_house,
    INT(NULLIF(id_owner, '')) AS id_owner,
    asp_email,
    asp_name,
    asp_list,
    DATE(NULLIF(dt_association, '')) AS dt_association
FROM
    datalake_gsheets_raw.sale_asp_portfolio_2022q2
