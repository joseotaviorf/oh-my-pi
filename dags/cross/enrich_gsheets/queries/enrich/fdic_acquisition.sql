SELECT
  a21.id_vx_security,
  a21.assignor_cnpj,
  a21.assignor_name,
  a21.withdraw_cnpj_cpf,
  a21.withdraw_name,
  a21.type,
  a21.asset_type,
  a21.key_field,
  a21.cmc7,
  REGEXP_REPLACE(a21.security_number, "\/*", "") AS security_number,
  CAST(REGEXP_EXTRACT(a21.security_number, "\/(.*)") AS INT) AS installment_number,
  a21.acquisition_value,
  a21.nominal_value,
  a21.invoice_number,
  DATE_FORMAT(a21.dt_acquisition, 'yyyyMM') AS accrual_year_month,
  a21.dt_emission,
  a21.dt_acquisition,
  a21.dt_due
FROM
  datalake_gsheets_clean.fdic_acquisition_2021 AS a21
UNION ALL
SELECT
  a22.id_vx_security,
  a22.assignor_cnpj,
  a22.assignor_name,
  a22.withdraw_cnpj_cpf,
  a22.withdraw_name,
  a22.type,
  a22.asset_type,
  a22.key_field,
  a22.cmc7,
  REGEXP_REPLACE(a22.security_number, "\/*", "") AS security_number,
  CAST(REGEXP_EXTRACT(a22.security_number, "\/(.*)") AS INT) AS installment_number,
  a22.acquisition_value,
  a22.nominal_value,
  a22.invoice_number,
  DATE_FORMAT(a22.dt_acquisition, 'yyyyMM') AS accrual_year_month,
  a22.dt_emission,
  a22.dt_acquisition,
  a22.dt_due
FROM
  datalake_gsheets_clean.fdic_acquisition_2022 AS a22
UNION ALL
SELECT
  a23.id_vx_security,
  a23.assignor_cnpj,
  a23.assignor_name,
  a23.withdraw_cnpj_cpf,
  a23.withdraw_name,
  a23.type,
  a23.asset_type,
  a23.key_field,
  a23.cmc7,
  REGEXP_REPLACE(a23.security_number, "\/*", "") AS security_number,
  CAST(REGEXP_EXTRACT(a23.security_number, "\/(.*)") AS INT) AS installment_number,
  a23.acquisition_value,
  a23.nominal_value,
  a23.invoice_number,
  DATE_FORMAT(a23.dt_acquisition, 'yyyyMM') AS accrual_year_month,
  a23.dt_emission,
  a23.dt_acquisition,
  a23.dt_due
FROM
  datalake_gsheets_clean.fdic_acquisition_2023 AS a23