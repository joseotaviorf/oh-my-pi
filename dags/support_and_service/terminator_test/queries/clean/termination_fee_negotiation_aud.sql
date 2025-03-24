SELECT
    id,
    termination_fee_id AS id_termination_fee,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    discount_value,
    final_amount,
    number_of_installments,
    payment_option,
    status,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_terminator_test_raw.termination_fee_negotiation_aud
