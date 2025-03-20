SELECT
    id,
    company_id AS id_company,
    banking_information_uuid AS uuid_banking_information,
    bank,
    agency_number,
    account_number,
    type,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_company_raw.banking_information