SELECT
  id,
  userid AS id_user,
  -- timestamp column is in milliseconds
  from_unixtime(`timestamp`/1000, 'yyyy-MM-dd HH:mm:ss') AS ts_revised
FROM
  datalake_kodak_raw.userrevisionentity