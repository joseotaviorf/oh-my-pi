SELECT
    id,
    contract_id AS id_contract,
    eligibility,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_condominium_payments_raw.condo_monitoring_eligibility
