SELECT
  bsc.id_status_change AS sk_broker_status_history,
  bsc.sk_broker,
  bsc.broker_status,
  CASE
    WHEN bsc.product_name = 'Rede Sale' THEN 'SALE'
    WHEN bsc.product_name = 'Rede Rent' THEN 'RENT'
  END AS business_context,
  bsc.status_origin,
  ROW_NUMBER() OVER (
    PARTITION BY
      bsc.sk_broker,
      COALESCE(
        CASE
          WHEN bsc.product_name = 'Rede Sale' THEN 'SALE'
          WHEN bsc.product_name = 'Rede Rent' THEN 'RENT'
        END,
        '__none__'
      )
    ORDER BY
      bsc.ts_start,
      bsc.id_status_change
  ) AS version,
  bsc.is_current,
  bsc.has_3p_access_control,
  bsc.ts_start,
  bsc.ts_end,
  CURRENT_TIMESTAMP() AS ts_load,
  YEAR(bsc.ts_start) AS year,
  MONTH(bsc.ts_start) AS month,
  DAY(bsc.ts_start) AS day
FROM
  datalake_brokers.broker_status_history AS bsc