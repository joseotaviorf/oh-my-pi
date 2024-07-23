SELECT
    id,
    gateway_loan_id AS id_gateway_loan,
    partner_reference_id AS id_partner_reference,
    installment_number,
    amortization_amount,
    interest_amount,
    expected_due_date AS ts_expected_due,
    created_at as ts_created,
    updated_at as ts_updated
FROM
    datalake_fastforward_homolog_raw.gateway_loan_installment
