SELECT
    id,
    delinquency_id AS id_delinquency,
    bill_item,
    version,
    description,
    value,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.delinquency_entry
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
