SELECT 
    r.id_reservation AS sk_reservation,
    MAX(rf.sk_contract) AS id_contract, 
    r.status,
    r.installments,
    r.cancellation_reason,
    r.value,
    r.ts_created,
    NOW() AS ts_load
FROM
    datalake_revenue_lines.reservation r
LEFT JOIN
    dw_public.fact_listing_rent_flows AS rf
        ON r.id_reservation = rf.sk_reservation
GROUP BY 1,3,4,5,6,7