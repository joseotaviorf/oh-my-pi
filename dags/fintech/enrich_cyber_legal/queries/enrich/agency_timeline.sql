WITH
expand_interval AS (
    SELECT
        id_contract,
        id_agency,
        main_agency_name,
        EXPLODE(
            SEQUENCE(
                dt_start_interval,
                GREATEST(dt_start_interval, IF(dt_end_interval = LAST_DAY(CURRENT_DATE), CURRENT_DATE, dt_end_interval))
            )
        ) AS dt_reference
    FROM
        datalake_cyber_legal_homolog.contract_agency_distribution
    WHERE
        creditor = 'QuintoAndar'
        AND dt_end_interval IS NOT NULL
        AND dt_start_interval <= dt_end_interval
),
contract_distribution AS (
  SELECT
    c.id_contract_external AS id_contract,
    hcd.agency,
    DATE(hcd.ts_distribution) AS dt_distribution
  FROM datalake_cyber_legal_homolog_clean.history_contract_distribution AS hcd
  LEFT JOIN datalake_cyber_legal_homolog_clean.contracts AS c
    ON hcd.id_contract = c.id_contract
  QUALIFY ROW_NUMBER() OVER(PARTITION BY c.id_contract_external, hcd.ts_distribution ORDER BY hcd.ts_redistribution, hcd.id_contract DESC) = 1
)
SELECT
  ei.id_contract,
  ei.id_agency,
  ei.main_agency_name,
  cd.agency AS original_agency_distribution,
  ei.dt_reference
FROM expand_interval AS ei
LEFT JOIN contract_distribution As cd
  ON cd.id_contract = ei.id_contract
    AND ei.dt_reference = cd.dt_distribution
