SELECT
    id,
    contract_id AS id_contract_ebdb,
    house_external_id AS id_house_ebdb,
    status,
    last_year_amount,
    year_tax_report,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_property_tax_raw.tax_report
