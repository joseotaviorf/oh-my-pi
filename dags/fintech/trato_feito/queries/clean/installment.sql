SELECT
    id,
    external_id AS id_external,
    negotiation_id AS id_negotiation,
    status,
    status_reason,
    adm_fee_amount,
    installment_fee_amount,
    debts_fee_amount,
    discount_amount,
    total_amount,
    due_date AS dt_due,
    expired_at AS ts_expired,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_trato_feito_raw.installment
