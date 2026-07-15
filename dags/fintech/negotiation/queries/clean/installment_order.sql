SELECT
    id,
    installment_id AS id_installment,
    order_id AS id_order,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_negotiation_raw.installment_order
