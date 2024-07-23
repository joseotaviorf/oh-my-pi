SELECT
    id,
    rev,
    revtype AS rev_type,
    installments_number AS installments,
    monthly_interest AS monthly_interest_rate,
    option_bucket,
    months_anticipated,
    valid_from AS ts_valid_from,
    valid_until AS ts_valid_until
FROM
    datalake_fastforward_homolog_raw.lra_installment_option_aud
