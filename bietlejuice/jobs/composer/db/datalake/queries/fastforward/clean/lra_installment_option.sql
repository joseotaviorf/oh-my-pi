SELECT
    id,
    installments_number AS installments,
    monthly_interest AS monthly_interest_rate,
    option_bucket,
    valid_from AS ts_valid_from,
    valid_until AS ts_valid_until,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_fastforward_raw.lra_installment_option
