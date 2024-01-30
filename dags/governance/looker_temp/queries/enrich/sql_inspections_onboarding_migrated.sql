WITH inspection_bookings AS (
  SELECT
    fib.sk_contract,
    di.type,
    MAX(fib.sk_inspection) AS sk_inspection
  FROM dw_public.fact_inspection_bookings AS fib
  LEFT JOIN dw_public.dim_inspection AS di
    ON fib.sk_inspection = di.sk_inspection
  GROUP BY
    1,
    2
)
SELECT
  fib.sk_contract,
  di.id_inspection,
  fib.sk_booking,
  TO_TIMESTAMP(CAST(NULLIF(fib.sk_inspected_date, -1) AS STRING), 'yyyyMMdd') AS inspection_date,
  TO_TIMESTAMP(CAST(NULLIF(fib.sk_booking_inspected_date, -1) AS STRING), 'yyyyMMdd') AS inspection_scheduled_date,
  TO_TIMESTAMP(CAST(NULLIF(fib.sk_booking_cancelled_date, -1) AS STRING), 'yyyyMMdd') AS dt_cancel,
  TO_TIMESTAMP(CAST(NULLIF(fib.sk_expired_date, -1) AS STRING), 'yyyyMMdd') AS expired_date,
  TO_TIMESTAMP(CAST(NULLIF(fib.sk_owner_approved_date, -1) AS STRING), 'yyyyMMdd') AS owner_approved_date,
  TO_TIMESTAMP(CAST(NULLIF(fib.sk_tenant_approved_date, -1) AS STRING), 'yyyyMMdd') AS tenant_approved_date,
  di.ts_first_synced AS ts_first_synced,
  di.ts_created AS ts_created,
  di.ts_expired AS ts_expired,
  di.ts_last_synced AS ts_last_synced,
  di.status,
  di.type
FROM inspection_bookings AS ib
INNER JOIN dw_public.fact_inspection_bookings AS fib
  ON ib.sk_contract = fib.sk_contract AND ib.sk_inspection = fib.sk_inspection
LEFT JOIN dw_public.dim_inspection AS di
  ON fib.sk_inspection = di.sk_inspection
WHERE
  NOT di.status IN ('Agendada', 'Cancelada', 'ContratoCancelado')
  AND di.type = 'Entrada'