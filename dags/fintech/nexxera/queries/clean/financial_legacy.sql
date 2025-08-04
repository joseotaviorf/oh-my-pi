SELECT
  col_1 AS id_registration,
  col_20 AS id_sale_type,
  col_21 AS id_flag,
  col_18 AS id_bank_grouper,
  col_9 AS id_bank_deposit,
  col_2 AS acquirer_name,
  col_3 AS establishment_cnpj,
  col_4 AS acquirer_pos,
  col_5 AS rv_summary_number,
  col_7 AS installment_number,
  CAST(col_10 AS INTEGER) AS agency_deposit,
  CAST(col_11 AS INTEGER) AS account_deposit,
  col_17 AS acquirer_code,
  col_19 AS voucher_flag,
  CAST(col_12 / 100 AS DECIMAL(10,2)) AS summary_installment_gross_amount,
  CAST(col_13 / 100 AS DECIMAL(10,2)) AS summary_installment_discount,
  CAST(col_14 / 100 AS DECIMAL(10,2)) AS summary_installment_net_amount,
  CAST(col_15 / 100 AS DECIMAL(10,2)) AS summary_installment_antecipation_discount,
  CAST(col_16 / 100 AS DECIMAL(10,2)) AS summary_installment_paid_amount,
  TO_DATE(col_8, 'ddMMyy') AS dt_installment_credit,
  TO_DATE(col_6, 'ddMMyy') AS dt_rv_summary,
  TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
  year,
  month,
  day
FROM
    datalake_nexxera_raw.financial
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND col_1 = 13
