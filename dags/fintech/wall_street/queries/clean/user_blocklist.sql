SELECT
  userId AS id_user,
  CAST(createdAt as TIMESTAMP) AS ts_created
FROM
  datalake_wall_street_raw.userblocklist
