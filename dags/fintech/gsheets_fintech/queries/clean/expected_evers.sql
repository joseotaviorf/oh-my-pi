SELECT
    Chave AS model_key,
    Modelo AS model_name,
    risk_category_canon AS risk_category_canon,
    CAST(REPLACE(Ever30mob3_EXPECTED, '%', '') AS DECIMAL(10,2)) AS ever_30_mob3_expected,
    CAST(REPLACE(Ever30mob3_UPPER_LIMIT, '%', '') AS DECIMAL(10,2)) AS ever_30_mob3_upper_limit,
    CAST(REPLACE(Ever30mob3_low_performance, '%', '') AS DECIMAL(10,2)) AS ever_30_mob3_low_performance,
    CAST(REPLACE(Ever60mob6_EXPECTED, '%', '') AS DECIMAL(10,2)) AS ever_60_mob6_expected,
    CAST(REPLACE(Ever60mob6_UPPER_LIMIT, '%', '') AS DECIMAL(10,2)) AS ever_60_mob6_upper_limit,
    CAST(REPLACE(Ever60mob6_low_performance, '%', '') AS DECIMAL(10, 2)) AS ever_60_mob6_low_performance,
    risk_category_agroup AS risk_category_group
FROM
    datalake_gsheets_raw.expected_evers
