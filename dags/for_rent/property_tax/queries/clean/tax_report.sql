SELECT
    id,
    contract_id AS id_contract_ebdb,
    house_external_id AS id_house_ebdb,
    status,
    last_year_amount,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year_tax_report,
    year,
    month,
    day
FROM 
    datalake_property_tax_raw.tax_report
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}