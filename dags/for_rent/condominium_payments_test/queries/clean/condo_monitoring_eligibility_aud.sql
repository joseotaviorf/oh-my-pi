SELECT
    id,
    contract_id AS id_contract,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    eligibility,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_condominium_payments_test_raw.condo_monitoring_eligibility_aud
