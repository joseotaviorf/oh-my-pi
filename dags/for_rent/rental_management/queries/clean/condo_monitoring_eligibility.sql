SELECT
    id,
    contract_id AS id_contract,
    eligibility,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rental_management_raw.condo_monitoring_eligibility
