WITH deduped AS (
    SELECT
        id,
        external_id AS id_external,
        version,
        name,
        email,
        phone_number,
        created_at AS ts_created,
        updated_at AS ts_updated,
        year,
        month,
        day,
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) AS rn
    FROM
        datalake_hub_services_raw.users
)
SELECT
    id,
    id_external,
    version,
    name,
    email,
    phone_number,
    ts_created,
    ts_updated,
    year,
    month,
    day,
    op_cdc,
    ts_cdc_transaction,
    ts_database_transaction
FROM
    deduped
WHERE
    rn = 1
