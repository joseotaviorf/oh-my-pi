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
  due_amount,
  paid_amount,
  dt_due,
  dt_paid,
  ts_ingested,
  year,
  month,
  day
FROM
  datalake_nexxera_clean.cnab_payments_341_seg_a
QUALIFY ROW_NUMBER() OVER (PARTITION BY company_use ORDER BY file_name DESC) = 1

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
  due_amount,
  paid_amount,
  dt_due,
  dt_paid,
  ts_ingested,
  year,
  month,
  day
FROM
  datalake_nexxera_clean.cnab_payments_341_seg_j
QUALIFY ROW_NUMBER() OVER (PARTITION BY company_use ORDER BY file_name DESC) = 1

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
  due_amount,
  paid_amount,
  dt_due,
  dt_paid,
  ts_ingested,
  year,
  month,
  day
FROM
  datalake_nexxera_clean.cnab_payments_341_seg_o
QUALIFY ROW_NUMBER() OVER (PARTITION BY company_use ORDER BY file_name DESC) = 1

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
  due_amount,
  paid_amount,
  dt_due,
  dt_paid,
  ts_ingested,
  year,
  month,
  day
FROM
  datalake_nexxera_clean.cnab_payments_237_seg_a
QUALIFY ROW_NUMBER() OVER (PARTITION BY company_use ORDER BY file_name DESC) = 1

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
  IF(TRIM(occurrence_code) = '00', TRUE, FALSE) AS is_done,
  due_amount,
  paid_amount,
  dt_due,
  dt_paid,
  ts_ingested,
  year,
  month,
  day
FROM
  df
