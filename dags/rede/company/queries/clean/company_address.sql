SELECT
    address_id AS id_address,
    company_id AS id_company,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_company_raw.company_address
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_address, id_company ORDER BY ts_updated DESC) = 1
