SELECT
    id,
    partner_id AS id_partner,
    hash,
    name AS file_name,
    type,
    url,
    file_byte,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_brokers_supply_processor_raw.file