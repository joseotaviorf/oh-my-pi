SELECT
  id,
  id_contract,
  charge_delay_in_days,
  installment_number,
  brokerage_fee,
  premium_fee,
  down_payment,
  version,
  ts_created,
  ts_updated
FROM (
  SELECT
    id,
    id_contract,
    charge_delay_in_days,
    installment_number,
    brokerage_fee,
    premium_fee,
    down_payment,
    version,
    ts_created,
    ts_updated,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) AS _w
  FROM datalake_owner_fees_clean.contract_brokerage_fee
) AS _t
WHERE
  _w = 1