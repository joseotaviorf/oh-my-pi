SELECT
    col_1 AS id_registration,
    col_2 AS group_name,
    col_3 AS group_cnpj,
    col_4 AS acquirer_name,
    col_5 AS establishment_cnpj,
    "adjustments" AS source_file,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.adjustments -- headers from adjustments files
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND col_1 = 04

UNION ALL

SELECT
    col_1 AS id_registration,
    col_2 AS group_name,
    col_3 AS group_cnpj,
    col_4 AS acquirer_name,
    col_5 AS establishment_cnpj,
    "financial" AS source_file,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.financial -- headers from financial files
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND col_1 = 04

UNION ALL

SELECT
    col_1 AS id_registration,
    col_2 AS group_name,
    col_3 AS group_cnpj,
    col_4 AS acquirer_name,
    col_5 AS establishment_cnpj,
    "inadvance" AS source_file,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.inadvance -- headers from inadvance files
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND col_1 = 04

UNION ALL

SELECT
    col_1 AS id_registration,
    col_2 AS group_name,
    col_3 AS group_cnpj,
    col_4 AS acquirer_name,
    col_5 AS establishment_cnpj,
    "sales" AS source_file,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.sales -- headers from sales files
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND col_1 = 04

UNION ALL

SELECT
    col_1 AS id_registration,
    col_2 AS group_name,
    col_3 AS group_cnpj,
    col_4 AS acquirer_name,
    col_5 AS establishment_cnpj,
    "transaction" AS source_file,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.transaction -- headers from transaction files
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND col_1 = 04
