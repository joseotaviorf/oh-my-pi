WITH charge_last_update AS (
  SELECT
    c.*,
    ROW_NUMBER() OVER (PARTITION BY c.id ORDER BY ts_updated DESC) AS rownum 
  FROM
    datalake_rental_guarantee_clean.charge AS c
)

SELECT
  id,
  id_guarantee,
  cancellation_reason,
  card_token,
  emv,
  installments,
  pix_link,
  qr_code,
  charge_status,
  charge_type,
  refund_amount,
  ts_created,
  ts_updated,
  year,
  month,
  day
FROM
  charge_last_update
WHERE
  rownum = 1