SELECT
    id,
    external_id AS id_external,
    negotiation_id AS id_negotiation,
    billing_id AS id_billing,
    interest_fee_amount,
    original_amount,
    fine_fee_amount,
    discount_amount,
    write_off AS is_write_off,
    due_date AS dt_due,
    offset_at AS dt_offset,
    DATE(write_off_at) AS dt_write_off,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_trato_feito_raw.debt