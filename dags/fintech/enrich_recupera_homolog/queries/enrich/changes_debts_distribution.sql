WITH
base AS (
  SELECT
    CASE
        WHEN id_creditor IN (1,4,7,8,9) THEN "IQ QuintoAndar"
        WHEN id_creditor IN (3,5) THEN "IQ QuintoCred"
        WHEN id_creditor IN (2,6) THEN "PP QuintoAndar"
    END AS creditor,
    id_contract,
    COALESCE(advisory,distributor) AS original_partner,
    CASE
        WHEN COALESCE(advisory,distributor) IN ("DACORDEV","DEVICEX","DEVICTIO", "DEVICFIN") THEN "EVICTIONS"
        WHEN COALESCE(advisory,distributor) = "DASSES" THEN "EXTERNO"
        WHEN COALESCE(advisory,distributor) IN ("DAT130","DAT3160","DAT61","DONBOARD","DACOINTE","DBOLPULA","DPREEVIC", "DACOVNQB") THEN "INTERNO"
        WHEN COALESCE(advisory,distributor) IN ("DLEGAL","DPCOB","DPCOBFR") THEN "INTERNO BLOQUEADO"
        WHEN COALESCE(advisory,distributor) IN ("DVAT130","DVAT3160","DVCOBINT", "DVESPBX") THEN "INTERNO VELO"
        WHEN COALESCE(advisory,distributor) IN ("V5PASCHW", "QPASCHWS","VPASCHWS") THEN "PASCHOALOTTO"
        WHEN COALESCE(advisory,distributor) IN ("VIAFWS","V5IAFWS", 'QIAFWS') THEN "IAF"
        WHEN COALESCE(advisory,distributor) IN ("DESPBXQT","DACOBLGQ","DCBINTQT") THEN "QUITEI BLOQUEADO"
        WHEN COALESCE(advisory,distributor) IN ("QWHELPWS","WEBHELP") THEN "WEBHELP"
        ELSE COALESCE(advisory,distributor)
    END AS partner,
    ts_snapshot
  FROM datalake_recupera_homolog.snapshot_daily_debts
),
capture_changes AS (
  SELECT
    creditor,
    id_contract,
    partner,
    ts_snapshot,
    IF(LAG(partner) OVER (PARTITION BY creditor,id_contract ORDER BY ts_snapshot) != partner, 1, 0) AS has_changed
  FROM base
),
segregate_groups AS (
  SELECT
    creditor,
    id_contract,
    partner,
    ts_snapshot,
    SUM(has_changed) OVER (PARTITION BY creditor,id_contract ORDER BY ts_snapshot) AS group
  FROM capture_changes
)
SELECT
  creditor,
  id_contract,
  partner,
  DATE(MIN(ts_snapshot)) AS dt_start_interval,
  DATE(MAX(ts_snapshot)) AS dt_end_interval,
  NOW() AS ts_load
FROM segregate_groups
GROUP BY
  creditor,
  id_contract,
  partner,
  group
