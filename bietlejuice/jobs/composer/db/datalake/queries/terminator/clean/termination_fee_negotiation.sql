SELECT
    id,
    termination_fee_id AS id_termination_fee,
    discount_value,
    final_amount,
    number_of_installments,
    payment_option,
    status,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM datalake_terminator_raw.termination_fee_negotiation