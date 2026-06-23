SELECT
    id,
    company_uuid AS uuid_company,
    agent_type,
    contract_type,
    availability_payment_mode,
    version,
    contract_start_date AS dt_contract_start,
    contract_end_date AS dt_contract_end,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_partner_payment_raw.company_contract_type
