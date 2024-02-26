SELECT 
  id_bank,
  SUBSTRING(metadata, 7, 3) as id_destination_bank,
  id_service_batch,
  substring_index(substring_index(file_name, '_', -3), '_', 1) as bank_account,
  record_type,
  record_sequence_number,
  segment_type,
  SUBSTRING(metadata, 1, 1) as transaction_type,
  SUBSTRING(metadata, 2, 2) as transaction_instruction_code,
  SUBSTRING(metadata, 4, 3) as centralizing_chamber_code,
  SUBSTRING(metadata, 10, 5) as destination_bank_agency,
  SUBSTRING(metadata, 15, 1) as destination_bank_agency_verification_digit,
  SUBSTRING(metadata, 16, 12) as destination_bank_account,
  SUBSTRING(metadata, 28, 1) as destination_bank_account_verification_digit,
  SUBSTRING(metadata, 29, 1) as destination_agency_account_verification_digit,
  SUBSTRING(metadata, 30, 30) as beneficiarys_name,
  SUBSTRING(metadata, 60, 20) as company_use,
  SUBSTRING(metadata, 88, 3) as currency,
  SUBSTRING(metadata, 91, 10) as currency_amount,
  SUBSTRING(metadata, 121, 20) as our_number,
  SUBSTRING(metadata, 164, 40) as notice,
  SUBSTRING(metadata, 204, 2) as doc_purpose,
  SUBSTRING(metadata, 206, 5) as ted_purpose,
  SUBSTRING(metadata, 211, 2) as additional_purpose,
  SUBSTRING(metadata, 213, 3) as cnab,
  SUBSTRING(metadata, 216, 1) as beneficiarys_notice,
  SUBSTRING(metadata, 217, 10) as occurrence_code,
  substring_index(file_name, '/', -1) as file_name,
  CAST (SUBSTRING(metadata, 106, 15)/100 AS DECIMAL(32,2)) as due_amount,
  CAST(SUBSTRING(metadata, 149, 15)/100 AS DECIMAL(32,2)) as paid_amount,
  TO_DATE(SUBSTRING(metadata, 80, 8), 'ddMMyyyy') as dt_due,
  TO_DATE(SUBSTRING(metadata, 141, 8), 'ddMMyyyy') as dt_paid,
  NOW() AS ts_ingested,
  year,
  month,
  day
FROM 
  datalake_nexxera_raw.cnab_payments
WHERE
  id_bank = '237'
AND 
  segment_type = 'A'