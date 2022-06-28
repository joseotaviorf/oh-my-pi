WITH files AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) AS rw
    FROM
        datalake_brokers_supply_processor_clean.file
)
SELECT
    id,
    id_partner,
    hash,
    file_name,
    type,
    url,
    file_byte,
    version,
    ts_created,
    ts_updated
FROM
    files