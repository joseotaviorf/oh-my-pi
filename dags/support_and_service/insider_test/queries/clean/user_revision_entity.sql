SELECT
   id,
   user_id as id_user,
   -- timestamp column is in milliseconds
   FROM_UNIXTIME(`timestamp`/1000, 'yyyy-MM-dd HH:mm:ss') AS ts_revised
FROM
   datalake_insider_test_raw.user_revision_entity
