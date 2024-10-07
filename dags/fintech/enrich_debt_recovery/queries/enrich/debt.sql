SELECT DISTINCT
    d.id_external AS id_invoice,
    n.id_debtor_external AS id_contract,
    CONCAT(dt.origin, "_", dt.type) AS debtor,
    b.our_number,
    b.external_sub_status,
    b.external_status,
    b.purpose,
    COALESCE(d.original_amount, ABS(b.due_amount)) AS due_amount,
    d.interest_fee_amount,
    d.fine_fee_amount,
    d.discount_amount,
    d.original_amount + d.interest_fee_amount + d.fine_fee_amount - d.discount_amount AS debt_amount,
    b.paid_amount,
    b.dt_due,
    b.dt_paid,
    DATE(b.ts_created) AS dt_created,
    DATE(d.ts_created) AS dt_debt_created,
    NOW() AS ts_load
FROM datalake_trato_feito_clean.debt AS d
INNER JOIN datalake_trato_feito_clean.negotiation AS n
    ON d.id_negotiation = n.id
LEFT JOIN datalake_trato_feito_clean.bill AS b
    ON d.id_external = b.id_external
LEFT JOIN  datalake_trato_feito_clean.debtor AS dt
    ON n.id_debtor = dt.id
WHERE d.id_negotiation IS NOT NULL
