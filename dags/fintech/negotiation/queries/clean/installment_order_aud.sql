SELECT
    id,
    installment_id AS id_installment,
    order_id AS id_order,
    rev,
    revtype,
    installment_id_mod AS mod_id_installment,
    order_id_mod AS mod_id_order,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_negotiation_raw.installment_order_aud
