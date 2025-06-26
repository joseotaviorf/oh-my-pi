SELECT
    t.id_payment_timeline AS sk_payment_timeline,
    p.id_payment AS sk_payment,
    t.id_business_key,
    t.id_finance_entity,
    t.datasource,
    t.timeline_status,
    t.payment_method_timeline,
    t.timeline_order,
    t.timeline_timestamp
FROM
    datalake_payments_platform.payment_timeline AS t
LEFT JOIN
    datalake_payments_platform.payment AS p
    ON t.id_business_key = p.id_business_key
