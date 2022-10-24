SELECT
    id,
    contract_id AS id_contract,
    description,
    value,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.contract_item
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}