SELECT
    id,
    propose_id AS id_propose,
    delinquency_id AS id_delinquency,
    lannister_payment_register_id AS id_lannister_payment_register,
    external_ticket_id AS id_external_ticket,
    status,
    payment_period,
    cancellation_reason,
    type,
    userinsert AS user_insert,
    userupdate AS user_update,
    total_value,
    due_month,
    created_at AS ts_created,
    updated_at AS ts_updated,
    approved_at AS ts_approved,
    keys_delivery_date AS ts_keys_delivered
FROM
    datalake_rental_guarantee_platform_raw.ticket_activation
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
