SELECT
    col_1 AS id_registration,
    "adjustments" AS source_file,
    col_2 AS group_name,
    col_3 AS group_cnpj,
    col_7 AS van_name,
    col_8 AS extract_type,
    col_9 AS layout_version,
    col_6 AS hr_file_generated,
    TO_DATE(col_5, 'ddMMyy') AS dt_file_generated,
    TO_DATE(col_4, 'ddMMyy') AS dt_file_reference,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.adjustments -- headers from adjustments files
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND col_1 = 00

UNION ALL

SELECT
    col_1 AS id_registration,
    "financial" AS source_file,
    col_2 AS group_name,
    col_3 AS group_cnpj,
    col_7 AS van_name,
    col_8 AS extract_type,
    col_9 AS layout_version,
    col_6 AS hr_file_generated,
    TO_DATE(col_5, 'ddMMyy') AS dt_file_generated,
    TO_DATE(col_4, 'ddMMyy') AS dt_file_reference,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.financial -- headers from financial files
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND col_1 = 00

UNION ALL

SELECT
    col_1 AS id_registration,
    "inadvance" AS source_file,
    col_2 AS group_name,
    col_3 AS group_cnpj,
    col_7 AS van_name,
    col_8 AS extract_type,
    col_9 AS layout_version,
    col_6 AS hr_file_generated,
    TO_DATE(col_5, 'ddMMyy') AS dt_file_generated,
    TO_DATE(col_4, 'ddMMyy') AS dt_file_reference,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.inadvance -- headers from inadvance files
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND col_1 = 00

UNION ALL

SELECT
    col_1 AS id_registration,
    "sales" AS source_file,
    col_2 AS group_name,
    col_3 AS group_cnpj,
    col_7 AS van_name,
    col_8 AS extract_type,
    col_9 AS layout_version,
    col_6 AS hr_file_generated,
    TO_DATE(col_5, 'ddMMyy') AS dt_file_generated,
    TO_DATE(col_4, 'ddMMyy') AS dt_file_reference,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.sales -- headers from sales files
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND col_1 = 00

UNION ALL

SELECT
    col_1 AS id_registration,
    "transaction" AS source_file,
    col_2 AS group_name,
    col_3 AS group_cnpj,
    col_7 AS van_name,
    col_8 AS extract_type,
    col_9 AS layout_version,
    col_6 AS hr_file_generated,
    TO_DATE(col_5, 'ddMMyy') AS dt_file_generated,
    TO_DATE(col_4, 'ddMMyy') AS dt_file_reference,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.transaction -- headers from transaction files
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND col_1 = 00
