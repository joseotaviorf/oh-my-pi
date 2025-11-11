SELECT
  CAST(matricula AS INTEGER) AS id_employee,
  nome_funcionario AS employee_name,
  verba AS allowance,
  descricao_de_verba AS allowance_description,
  CAST(REPLACE(referencia_0325, ',', '.') AS DOUBLE) AS reference_0325,
  CAST(REPLACE(referencia_0425, ',', '.') AS DOUBLE) AS reference_0425,
  CAST(REPLACE(referencia_0525, ',', '.') AS DOUBLE) AS reference_0525,
  CAST(REPLACE(referencia_0625, ',', '.') AS DOUBLE) AS reference_0625,
  CAST(REPLACE(referencia_0725, ',', '.') AS DOUBLE) AS reference_0725,
  CAST(REPLACE(referencia_0825, ',', '.') AS DOUBLE) AS reference_0825,
  CAST(REPLACE(referencia_0925, ',', '.') AS DOUBLE) AS reference_0925,
  CAST(REPLACE(referencia_1025, ',', '.') AS DOUBLE) AS reference_1025,
  CAST(REPLACE(referencia_1125, ',', '.') AS DOUBLE) AS reference_1125,
  CAST(REPLACE(referencia_1225, ',', '.') AS DOUBLE) AS reference_1225
FROM
  datalake_gsheets_raw.data_platform_engineering_on_call_tracking_hours
