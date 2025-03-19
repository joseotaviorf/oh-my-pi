SELECT
    query,
    query_hash,
    base64(query_hash) AS query_hash_string,
    average_execution_time AS average_execution_time_in_milliseconds
FROM
    datalake_metabase_raw.query
