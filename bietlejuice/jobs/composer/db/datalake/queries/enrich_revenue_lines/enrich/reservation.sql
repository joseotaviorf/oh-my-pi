SELECT 
    r.id_reservation,
    r.status,
    r.installments,
    r.cancellation_reason,
    CAST(r.value AS DECIMAL(19,2)) as value,
    r.ts_created
FROM
    datalake_kill_queue.reservation AS r
WHERE
    r.id_reservation > 0
    AND r.is_ongoing IS NULL
    AND (r.status IN ('FINISHED', 'CHARGED') OR (r.status = 'CANCELED' AND (r.cancellation_reason = 'TENANT_GAVE_UP' OR r.cancellation_reason like '%WITHOUT_CHARGE_BACK')))