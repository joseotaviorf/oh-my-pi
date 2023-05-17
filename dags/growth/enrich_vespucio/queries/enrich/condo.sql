SELECT
    *
FROM
    datalake_vespucio.condo_incremental
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id, source ORDER BY ts_updated) = 1