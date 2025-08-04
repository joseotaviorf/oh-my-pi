SELECT
    col_1 AS id_registration,
    "adjustments" AS source_file,
    col_2 AS group_name,
    col_3 AS group_cnpj,
    col_4 AS total_credited_acquirers,
    col_5 AS total_file_records,
    CAST(col_6 / 100 AS DECIMAL(15,2)) AS sale_installments_net_value,
    CAST(col_7 / 100 AS DECIMAL(15,2)) AS summary_anticipated_value,
    CAST(col_8 / 100 AS DECIMAL(15,2)) AS credit_adjustments_value,
    CAST(col_9 / 100 AS DECIMAL(15,2)) AS debit_adjustments_value,
    CAST(col_10 / 100 AS DECIMAL(15,2)) AS compensated_adjustments_value,
    CAST(col_11 / 100 AS DECIMAL(15,2)) AS legacy_summary_installments_value,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.adjustments -- headers from adjustments files
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND col_1 = 99

UNION ALL

SELECT
    col_1 AS id_registration,
    "financial" AS source_file,
    col_2 AS group_name,
    col_3 AS group_cnpj,
    col_4 AS total_credited_acquirers,
    col_5 AS total_file_records,
    CAST(col_6 / 100 AS DECIMAL(15,2)) AS sale_installments_net_value,
    CAST(col_7 / 100 AS DECIMAL(15,2)) AS summary_anticipated_value,
    CAST(col_8 / 100 AS DECIMAL(15,2)) AS credit_adjustments_value,
    CAST(col_9 / 100 AS DECIMAL(15,2)) AS debit_adjustments_value,
    CAST(col_10 / 100 AS DECIMAL(15,2)) AS compensated_adjustments_value,
    CAST(col_11 / 100 AS DECIMAL(15,2)) AS legacy_summary_installments_value,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.financial -- headers from financial files
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND col_1 = 99

UNION ALL

SELECT
    col_1 AS id_registration,
    "inadvance" AS source_file,
    col_2 AS group_name,
    col_3 AS group_cnpj,
    col_4 AS total_credited_acquirers,
    col_5 AS total_file_records,
    CAST(col_6 / 100 AS DECIMAL(15,2)) AS sale_installments_net_value,
    CAST(col_7 / 100 AS DECIMAL(15,2)) AS summary_anticipated_value,
    CAST(col_8 / 100 AS DECIMAL(15,2)) AS credit_adjustments_value,
    CAST(col_9 / 100 AS DECIMAL(15,2)) AS debit_adjustments_value,
    CAST(col_10 / 100 AS DECIMAL(15,2)) AS compensated_adjustments_value,
    CAST(col_11 / 100 AS DECIMAL(15,2)) AS legacy_summary_installments_value,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.inadvance -- headers from inadvance files
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND col_1 = 99

UNION ALL

SELECT
    col_1 AS id_registration,
    "sales" AS source_file,
    col_2 AS group_name,
    col_3 AS group_cnpj,
    col_4 AS total_credited_acquirers,
    col_5 AS total_file_records,
    CAST(col_6 / 100 AS DECIMAL(15,2)) AS sale_installments_net_value,
    CAST(col_7 / 100 AS DECIMAL(15,2)) AS summary_anticipated_value,
    CAST(col_8 / 100 AS DECIMAL(15,2)) AS credit_adjustments_value,
    CAST(col_9 / 100 AS DECIMAL(15,2)) AS debit_adjustments_value,
    CAST(col_10 / 100 AS DECIMAL(15,2)) AS compensated_adjustments_value,
    CAST(col_11 / 100 AS DECIMAL(15,2)) AS legacy_summary_installments_value,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.sales -- headers from sales files
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND col_1 = 99

UNION ALL

SELECT
    col_1 AS id_registration,
    "transaction" AS source_file,
    col_2 AS group_name,
    col_3 AS group_cnpj,
    col_4 AS total_credited_acquirers,
    col_5 AS total_file_records,
    CAST(col_6 / 100 AS DECIMAL(15,2)) AS sale_installments_net_value,
    CAST(col_7 / 100 AS DECIMAL(15,2)) AS summary_anticipated_value,
    CAST(col_8 / 100 AS DECIMAL(15,2)) AS credit_adjustments_value,
    CAST(col_9 / 100 AS DECIMAL(15,2)) AS debit_adjustments_value,
    CAST(col_10 / 100 AS DECIMAL(15,2)) AS compensated_adjustments_value,
    CAST(col_11 / 100 AS DECIMAL(15,2)) AS legacy_summary_installments_value,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.transaction -- headers from transaction files
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND col_1 = 99
