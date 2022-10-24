SELECT
    id,
    external_id AS id_external,
    negotiation_id AS id_negotiation,
    bill_id AS id_bill,
    status,
    adm_fee_amount,
    installment_fee_amount,
    debts_fee_amount,
    discount_amount,
    total_amount,
    due_date AS dt_due,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_trato_feito_raw.installment