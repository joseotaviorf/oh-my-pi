SELECT
  id,
  id_contract_ebdb,
  id_house_ebdb,
  status,
  last_year_amount,
  year_tax_report,
  ts_created,
  ts_updated
FROM (
  SELECT
    id,
    id_contract_ebdb,
    id_house_ebdb,
    status,
    last_year_amount,
    year_tax_report,
    ts_created,
    ts_updated,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) AS _w
  FROM datalake_property_tax_clean.tax_report
) AS _t
WHERE
  _w = 1