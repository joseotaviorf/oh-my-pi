WITH df AS (

SELECT
  id_bank,
  bank_account,
  beneficiarys_name,
  cpf_cnpj,
  segment_type,
  company_use,
  our_number,
  occurrence_code,
  file_name,
  due_amount,
  paid_amount,
  dt_due,
  dt_paid,
  IF(bank_account IN ('433065', '452586'), TO_DATE(SUBSTRING(file_name, 16, 6), 'ddMMyy'), TO_DATE(SUBSTRING(file_name, 16, 6), 'yyMMdd')) AS dt_received,
  ts_ingested,
  year,
  month,
  day
FROM
  datalake_nexxera_clean.cnab_payments_341_seg_a

UNION ALL

SELECT
  id_bank,
  bank_account,
  beneficiarys_name,
  NULL AS cpf_cnpj,
  segment_type,
  company_use,
  our_number,
  occurrence_code,
  file_name,
  due_amount,
  paid_amount,
  dt_due,
  dt_paid,
  TO_DATE(SUBSTRING(file_name, 16, 6), 'yyMMdd') AS dt_received,
  ts_ingested,
  year,
  month,
  day
FROM
  datalake_nexxera_clean.cnab_payments_341_seg_j

UNION ALL

SELECT
  id_bank,
  bank_account,
  NULL AS beneficiarys_name,
  NULL AS cpf_cnpj,
  segment_type,
  company_use,
  our_number,
  occurrence_code,
  file_name,
  due_amount,
  paid_amount,
  dt_due,
  dt_paid,
  TO_DATE(SUBSTRING(file_name, 16, 6), 'yyMMdd') AS dt_received,
  ts_ingested,
  year,
  month,
  day
FROM
  datalake_nexxera_clean.cnab_payments_341_seg_o

UNION ALL

SELECT
  id_bank,
  bank_account,
  beneficiarys_name,
  NULL AS cpf_cnpj,
  segment_type,
  company_use,
  our_number,
  occurrence_code,
  file_name,
  due_amount,
  paid_amount,
  dt_due,
  dt_paid,
  TO_DATE(SUBSTRING(file_name, 15, 6), 'yyMMdd') AS dt_received,
  ts_ingested,
  year,
  month,
  day
FROM
  datalake_nexxera_clean.cnab_payments_237_seg_a

)

SELECT DISTINCT
  id_bank,
  bank_account,
  segment_type,
  CASE
    WHEN segment_type = 'J' THEN 'Liquidação de títulos (boletos) em cobrança, PIX QR CODE'
    WHEN segment_type = 'O' THEN 'Pagamento de Contas de Concessionárias e Tributos com código de barras'
    WHEN segment_type = 'A' THEN 'Pagamentos através de cheque, OP, DOC, TED, PIX Transferência e crédito em conta corrente'
  END as segment_type_details,
  TRIM(company_use) AS company_use,
  TRIM(our_number) AS our_number,
  UPPER(TRIM(beneficiarys_name)) AS beneficiarys_name,
  cpf_cnpj,
  TRIM(occurrence_code) AS occurrence_code,
  file_name,
  ROW_NUMBER() OVER (PARTITION BY TRIM(our_number) ORDER BY dt_received, file_name) AS payment_attempts,
  IF(ROW_NUMBER() OVER (PARTITION BY TRIM(our_number) ORDER BY dt_received DESC, file_name DESC) = 1, TRUE, FALSE) AS is_latest_attempt,
  due_amount,
  paid_amount,
  dt_due,
  dt_paid,
  dt_received,
  ts_ingested,
  year,
  month,
  day
FROM
  df
