SELECT
    gl_acctbp_code,
    name,
    agrupador1 AS grouper,
    agrupador2 AS subgrouper,
    fs_grouper,
    entity_code,
    city,
    regime,
    iss_rate,
    pis_rate,
    cof_rate AS cofins_rate,
    iss_account,
    pis_account,
    cofins_account
FROM
    datalake_gsheets_raw.tax_calculation
