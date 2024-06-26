SELECT
    id,
    installment_id AS id_installment,
    order_id AS id_order,
    payment_entity_id AS id_payment_entity,
    charge_id AS id_charge,
    charge_method,
    charge_gateway,
    status,
    request_payload,
    response_payload,
    user_data,
    metadata,
    due_amount,
    paid_amount,
    paid_date AS dt_paid,
    due_date AS dt_due,
    created_at AS ts_created,
    updated_at AS ts_updated,
    last_received_at AS ts_last_received,
    start_processing_at AS ts_start_processing
FROM
    datalake_trato_feito_raw.installment_charges
