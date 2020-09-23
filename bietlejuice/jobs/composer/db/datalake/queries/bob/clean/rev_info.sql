SELECT
    rev,
    CAST(FROM_UNIXTIME(CAST(revtstmp AS BIGINT)/1000) AS TIMESTAMP) AS ts_created
FROM datalake_bob_raw.revinfo