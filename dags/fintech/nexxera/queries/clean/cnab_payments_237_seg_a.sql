SELECT 
  id_bank,
  SUBSTRING(metadata, 7, 3) as id_destination_bank,
  id_service_batch,
  substring_index(substring_index(file_name, '_', -3), '_', 1) AS bank_account,
  record_type,
  record_sequence_number,
  segment_type,
  SUBSTRING(metadata, 1, 1) AS transaction_type,
  SUBSTRING(metadata, 2, 2) AS transaction_instruction_code,
  SUBSTRING(metadata, 4, 3) AS centralizing_chamber_code,
  SUBSTRING(metadata, 10, 5) AS destination_bank_agency,
  SUBSTRING(metadata, 15, 1) AS destination_bank_agency_verification_digit,
  SUBSTRING(metadata, 16, 12) AS destination_bank_account,
  SUBSTRING(metadata, 28, 1) AS destination_bank_account_verification_digit,
  SUBSTRING(metadata, 29, 1) AS destination_agency_account_verification_digit,
  TRIM(SUBSTRING(metadata, 30, 30)) AS beneficiarys_name,
  TRIM(SUBSTRING(metadata, 60, 20)) AS company_use,
  SUBSTRING(metadata, 88, 3) AS currency,
  SUBSTRING(metadata, 91, 10) AS currency_amount,
  TRIM(SUBSTRING(metadata, 121, 20)) AS our_number,
  SUBSTRING(metadata, 164, 40) AS notice,
  SUBSTRING(metadata, 204, 2) AS doc_purpose,
  SUBSTRING(metadata, 206, 5) AS ted_purpose,
  SUBSTRING(metadata, 211, 2) AS additional_purpose,
  SUBSTRING(metadata, 213, 3) AS cnab,
  SUBSTRING(metadata, 216, 1) AS beneficiarys_notice,
  TRIM(SUBSTRING(metadata, 217, 10)) AS occurrence_code,
  substring_index(file_name, '/', -1) AS file_name,
  CAST (SUBSTRING(metadata, 106, 15)/100 AS DECIMAL(32,2)) AS due_amount,
  CAST(SUBSTRING(metadata, 149, 15)/100 AS DECIMAL(32,2)) AS paid_amount,
  TO_DATE(SUBSTRING(metadata, 80, 8), 'ddMMyyyy') AS dt_due,
  TO_DATE(SUBSTRING(metadata, 141, 8), 'ddMMyyyy') AS dt_paid,
  TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
  year,
  month,
  day
FROM 
  datalake_nexxera_raw.cnab_payments
WHERE
  id_bank = '237'
AND 
  segment_type = 'A'
AND
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'