SELECT
    id,
    company_id AS id_company,
    banking_information_uuid AS uuid_banking_information,
    bank,
    agency_number,
    account_number,
    type,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    company_id_mod AS mod_id_company,
    banking_information_uuid_mod AS mod_uuid_banking_information,
    bank_mod AS mod_bank,
    agency_number_mod AS mod_agency_number,
    account_number_mod AS mod_account_number,
    type_mod AS mod_type,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_company_raw.banking_information_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
