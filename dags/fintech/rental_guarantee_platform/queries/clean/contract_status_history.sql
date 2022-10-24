SELECT
    id,
    contract_id AS id_contract,
    edited_by_person AS id_edited_by_person,
    status,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.contract_status_history
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}