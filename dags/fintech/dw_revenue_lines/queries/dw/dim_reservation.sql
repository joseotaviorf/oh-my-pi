SELECT
    r.id_reservation AS sk_reservation,
    MAX(rf.sk_contract) AS id_contract,
    r.status,
    r.cancellation_reason,
    r.total_installments,
    r.monthly_value,
    r.total_value,
    r.accrual_month,
    r.dt_end_payment,
    r.dt_created,
    NOW() AS ts_load
FROM
    datalake_revenue_lines.reservation r
INNER JOIN
    dw_rent.fact_listing_rent_flows AS rf
        ON r.id_reservation = rf.sk_reservation
WHERE
    rf.sk_contract > 0
    AND r.id_reservation > 0
    AND r.is_ongoing IS NULL
    AND (r.status IN ('FINISHED', 'CHARGED') OR (r.status = 'CANCELED' AND (r.cancellation_reason = 'TENANT_GAVE_UP' OR r.cancellation_reason LIKE '%WITHOUT_CHARGE_BACK')))
GROUP BY 1,3,4,5,6,7,8,9,10,11
