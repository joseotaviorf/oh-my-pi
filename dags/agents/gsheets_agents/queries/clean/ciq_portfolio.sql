SELECT
  CAST(ciq_id AS LONG) AS id_partner,
  carteira AS portfolio_user_name,
  cluster AS cluster_name,
  ts_load AS ts_created
FROM
  datalake_gsheets_raw.ciq_portfolio