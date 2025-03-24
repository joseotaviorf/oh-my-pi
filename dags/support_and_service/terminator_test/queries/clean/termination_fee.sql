SELECT
    id,
    termination_id AS id_termination,
    period_start_charge AS dt_period_start_charge,
    contract_rental_amount,
    period_end_charge AS dt_period_end_charge,
    period_min_end_date AS dt_period_min_end,
    period_fee_end_date AS dt_period_fee_end,
    period_occupancy_days,
    period_fee_missing_days,
    period_fee_days,
    period_fee_months,
    fee_ratio,
    fee_factor,
    fee_prior_notice AS is_fee_prior_notice,
    tenant_amount,
    tenant_payment_method,
    landlord_amount,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_terminator_test_raw.termination_fee
