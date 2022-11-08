SELECT
  u.id AS id_user,
  u.id_agent, -- is the same ID as the id_agent_rep
  u.id_sales_rep,
  u.id_affiliates,
  u.id_photographer_data,
  u.id_country,
  u.id_state,
  COALESCE(ct.code, 'Undefined') AS country_code,
  u.ts_created,
  u.ts_updated
FROM
  datalake_ebdb_clean.user AS u
LEFT JOIN
  datalake_ebdb_clean.country AS ct
    ON ct.id = u.id_country