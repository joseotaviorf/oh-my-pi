SELECT
    col_1 AS id_registration,
    col_21 AS id_flag,
    col_9 AS id_bank_deposit,
    col_19 AS acquirer_code,
    col_2 AS acquirer_name,
    col_10 AS agency_deposit,
    col_11 AS account_deposit,
    col_23 AS sale_type,
    col_3 AS establishment_cnpj,
    col_4 AS acquirer_pos,
    col_20 AS conciliation_status,
    col_5 AS rv_summary_number,
    col_22 AS total_installments,
    col_7 AS summary_installment_number,
    CAST(col_12 / 100 AS DECIMAL(10,2)) AS inicial_antecipation_value,
    CAST(col_13 / 100 AS DECIMAL(10,2)) AS discount_antecipation_value,
    CAST(col_14 / 100 AS DECIMAL(10,2)) AS credit_net_value,
    CAST(col_15 / 100 AS DECIMAL(10,2)) AS original_installment_net_value,
    CAST(col_17 / 100 AS DECIMAL(10,2)) AS original_installment_gross_value,
    CAST(col_18 / 100 AS DECIMAL(10,2)) AS discount_installment_gross_value,
    TO_DATE(col_8, 'ddMMyy') AS dt_credit_installment,
    TO_DATE(col_16, 'ddMMyy') AS dt_summary_sale,
    TO_DATE(col_6, 'ddMMyy') AS dt_due,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.inadvance
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND col_1 = 10
