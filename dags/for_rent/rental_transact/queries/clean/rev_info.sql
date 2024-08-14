SELECT
    rev,
    CAST(FROM_UNIXTIME(CAST(revtstmp AS BIGINT)/1000) AS TIMESTAMP) AS ts_rev
FROM
    datalake_rental_transact_raw.revinfo