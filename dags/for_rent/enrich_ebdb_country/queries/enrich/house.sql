SELECT
  h.id AS id_house,
  ct.id AS id_country,
  h.id_state,
  h.id_region,
  COALESCE(ct.code, 'Undefined') AS country_code,
  h.dt_creation AS ts_created,
  h.ts_updated
FROM
  datalake_ebdb_clean.house AS h
LEFT JOIN
  datalake_ebdb_clean.region AS r
    ON r.id = h.id_region
LEFT JOIN
  datalake_ebdb_clean.region AS mr
    ON mr.id = r.id_parent_region
LEFT JOIN
  datalake_ebdb_clean.region AS c
    ON c.id = mr.id_parent_region
LEFT JOIN
  datalake_ebdb_clean.state AS s
    ON s.id = COALESCE(h.id_state, r.id_state, mr.id_state, c.id_state)
LEFT JOIN
  datalake_ebdb_clean.country AS ct
    ON ct.id = s.id_country