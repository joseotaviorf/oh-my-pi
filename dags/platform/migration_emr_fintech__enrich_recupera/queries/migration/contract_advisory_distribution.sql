WITH distinct_contract_customer AS (
  SELECT DISTINCT
    id_contract,
    id_customer
  FROM datalake_recupera_clean.contracts
), operational_records AS (
  SELECT
    id_customer,
    advisory,
    distributor,
    ts_customer_status_last_update,
    dt_snapshot
  FROM (
    SELECT DISTINCT
      id_customer,
      advisory_code AS advisory,
      distributor_code AS distributor,
      ts_customer_status_last_update,
      MAKE_DATE(year, month, day) AS dt_snapshot,
      ROW_NUMBER() OVER (PARTITION BY id_customer, MAKE_DATE(year, month, day) ORDER BY ts_last_update DESC) AS _w,
      year,
      month,
      day,
      ts_last_update
    FROM datalake_recupera_clean.operational_records
    WHERE
      id_creditor = '1' /* filter quintoandar */
      AND MAKE_DATE(year, month, day) BETWEEN DATE_TRUNC('MONTH', CURRENT_DATE - INTERVAL '48' MONTH) AND CURRENT_DATE - INTERVAL '1' DAY
  ) AS _t
  WHERE
    _w = 1
)
SELECT
  id_contract,
  advisory,
  distributor,
  partner,
  dt_snapshot
FROM (
  SELECT DISTINCT
    c.id_contract,
    ors.advisory,
    ors.distributor,
    CASE
      WHEN COALESCE(ors.advisory, ors.distributor) IN ('DACORDEV', 'DEVICEX', 'DEVICTIO', 'DEVICFIN')
      THEN 'EVICTIONS'
      WHEN COALESCE(ors.advisory, ors.distributor) = 'DASSES'
      THEN 'EXTERNO'
      WHEN COALESCE(ors.advisory, ors.distributor) IN ('DAT130', 'DAT3160', 'DAT61', 'DONBOARD', 'DACOINTE', 'DBOLPULA', 'DPREEVIC', 'DACOVNQB')
      THEN 'INTERNO'
      WHEN COALESCE(ors.advisory, ors.distributor) IN ('DLEGAL', 'DPCOB', 'DPCOBFR')
      THEN 'INTERNO BLOQUEADO'
      WHEN COALESCE(ors.advisory, ors.distributor) LIKE '%PASCH%'
      THEN 'PASCHOALOTTO'
      WHEN COALESCE(ors.advisory, ors.distributor) IN ('VIAFWS', 'V5IAFWS', 'QIAFWS')
      THEN 'IAF'
      WHEN COALESCE(ors.advisory, ors.distributor) IN ('DESPBXQT', 'DACOBLGQ', 'DCBINTQT')
      THEN 'QUITEI BLOQUEADO'
      WHEN COALESCE(ors.advisory, ors.distributor) IN ('QWHELPWS', 'WEBHELP')
      THEN 'WEBHELP'
      ELSE COALESCE(ors.advisory, ors.distributor)
    END AS partner,
    ors.dt_snapshot,
    ROW_NUMBER() OVER (PARTITION BY c.id_contract, ors.dt_snapshot ORDER BY ors.ts_customer_status_last_update DESC) AS _w,
    ors.ts_customer_status_last_update
  FROM operational_records AS ors
  LEFT JOIN distinct_contract_customer AS c
    ON ors.id_customer = c.id_customer
) AS _t
WHERE
  _w = 1
