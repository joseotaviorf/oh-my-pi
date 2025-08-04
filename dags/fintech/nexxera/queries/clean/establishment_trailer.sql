SELECT
    col_1 AS id_registration,
    "adjustments" AS source_file,
    col_2 AS establishment_name,
    col_3 AS establishment_cnpj,
    col_4 AS acquirer_name,
    col_5 AS group_name,
    CAST(col_6 / 100 AS DECIMAL(15,2)) AS sale_installments_net_value,
    CAST(col_7 / 100 AS DECIMAL(15,2)) AS summary_anticipated_value,
    CAST(col_8 / 100 AS DECIMAL(15,2)) AS credit_adjustments_value,
    CAST(col_9 / 100 AS DECIMAL(15,2)) AS debit_adjustments_value,
    CAST(col_10 / 100 AS DECIMAL(15,2)) AS compensated_adjustments_value,
    CAST(col_11 / 100 AS DECIMAL(15,2)) AS legacy_summary_installments_value,
    CAST(col_12 AS INT) AS total_sale_installments,
    CAST(col_13 AS INT) AS total_sale_statements,
    CAST(col_14 AS INT) AS total_sale_summary,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.adjustments -- headers from adjustments files
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND col_1 = 96

UNION ALL

SELECT
    col_1 AS id_registration,
    "financial" AS source_file,
    col_2 AS establishment_name,
    col_3 AS establishment_cnpj,
    col_4 AS acquirer_name,
    col_5 AS group_name,
    CAST(col_6 / 100 AS DECIMAL(15,2)) AS sale_installments_net_value,
    CAST(col_7 / 100 AS DECIMAL(15,2)) AS summary_anticipated_value,
    CAST(col_8 / 100 AS DECIMAL(15,2)) AS credit_adjustments_value,
    CAST(col_9 / 100 AS DECIMAL(15,2)) AS debit_adjustments_value,
    CAST(col_10 / 100 AS DECIMAL(15,2)) AS compensated_adjustments_value,
    CAST(col_11 / 100 AS DECIMAL(15,2)) AS legacy_summary_installments_value,
    CAST(col_12 AS INT) AS total_sale_installments,
    CAST(col_13 AS INT) AS total_sale_statements,
    CAST(col_14 AS INT) AS total_sale_summary,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.financial -- headers from financial files
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND col_1 = 96

UNION ALL

SELECT
    col_1 AS id_registration,
    "inadvance" AS source_file,
    col_2 AS establishment_name,
    col_3 AS establishment_cnpj,
    col_4 AS acquirer_name,
    col_5 AS group_name,
    CAST(col_6 / 100 AS DECIMAL(15,2)) AS sale_installments_net_value,
    CAST(col_7 / 100 AS DECIMAL(15,2)) AS summary_anticipated_value,
    CAST(col_8 / 100 AS DECIMAL(15,2)) AS credit_adjustments_value,
    CAST(col_9 / 100 AS DECIMAL(15,2)) AS debit_adjustments_value,
    CAST(col_10 / 100 AS DECIMAL(15,2)) AS compensated_adjustments_value,
    CAST(col_11 / 100 AS DECIMAL(15,2)) AS legacy_summary_installments_value,
    CAST(col_12 AS INT) AS total_sale_installments,
    CAST(col_13 AS INT) AS total_sale_statements,
    CAST(col_14 AS INT) AS total_sale_summary,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.inadvance -- headers from inadvance files
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND col_1 = 96

UNION ALL


SELECT
    col_1 AS id_registration,
    "sales" AS source_file,
    col_2 AS establishment_name,
    col_3 AS establishment_cnpj,
    col_4 AS acquirer_name,
    col_5 AS group_name,
    CAST(col_6 / 100 AS DECIMAL(15,2)) AS sale_installments_net_value,
    CAST(col_7 / 100 AS DECIMAL(15,2)) AS summary_anticipated_value,
    CAST(col_8 / 100 AS DECIMAL(15,2)) AS credit_adjustments_value,
    CAST(col_9 / 100 AS DECIMAL(15,2)) AS debit_adjustments_value,
    CAST(col_10 / 100 AS DECIMAL(15,2)) AS compensated_adjustments_value,
    CAST(col_11 / 100 AS DECIMAL(15,2)) AS legacy_summary_installments_value,
    CAST(col_12 AS INT) AS total_sale_installments,
    CAST(col_13 AS INT) AS total_sale_statements,
    CAST(col_14 AS INT) AS total_sale_summary,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.sales -- headers from sales files
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND col_1 = 96

UNION ALL


SELECT
    col_1 AS id_registration,
    "transaction" AS source_file,
    col_2 AS establishment_name,
    col_3 AS establishment_cnpj,
    col_4 AS acquirer_name,
    col_5 AS group_name,
    CAST(col_6 / 100 AS DECIMAL(15,2)) AS sale_installments_net_value,
    CAST(col_7 / 100 AS DECIMAL(15,2)) AS summary_anticipated_value,
    CAST(col_8 / 100 AS DECIMAL(15,2)) AS credit_adjustments_value,
    CAST(col_9 / 100 AS DECIMAL(15,2)) AS debit_adjustments_value,
    CAST(col_10 / 100 AS DECIMAL(15,2)) AS compensated_adjustments_value,
    CAST(col_11 / 100 AS DECIMAL(15,2)) AS legacy_summary_installments_value,
    CAST(col_12 AS INT) AS total_sale_installments,
    CAST(col_13 AS INT) AS total_sale_statements,
    CAST(col_14 AS INT) AS total_sale_summary,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.transaction -- headers from transaction files
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND col_1 = 96
