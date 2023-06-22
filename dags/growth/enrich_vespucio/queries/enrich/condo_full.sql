SELECT
    MD5(CONCAT(id, source)) AS id_condo,
    *
FROM
    datalake_vespucio.condo_incremental
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id, source ORDER BY ts_updated) = 1