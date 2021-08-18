SELECT
  id,
  ip,
  confirmacao AS confirmation,
  arquivo AS file,
  CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
  datalake_casa_mineira_crm_raw.ficha