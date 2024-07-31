SELECT
    id,
    long_term_anticipation_id AS id_long_term_anticipation,
    partner_reference_id AS id_partner_reference,
    installment_number,
    status,
    amount,
    interest_value,
    due_at AS ts_due,
    expected_due_date AS ts_expected_due,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_fastforward_raw.lra_installment
