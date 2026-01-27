SELECT
  	id,
  	incremental_id AS id_incremental,
  	destination,
  	headers,
  	payload,
  	CASE
  	  	WHEN published = 0 THEN FALSE
  	  	ELSE TRUE
  	END as is_published,
  	message_partition,
  	TIMESTAMP_MILLIS(creation_time) AS ts_created
FROM
  	datalake_rental_transact_raw.message