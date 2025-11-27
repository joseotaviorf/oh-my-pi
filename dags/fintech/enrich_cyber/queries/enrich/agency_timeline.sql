WITH
expand_interval AS (
    SELECT
        cad.id_contract,
        cad.id_agency,
        cad.main_agency_name,
        EXPLODE(
            SEQUENCE(
                cad.dt_start_interval,
                GREATEST(cad.dt_start_interval, IF(cad.dt_end_interval = LAST_DAY(CURRENT_DATE), CURRENT_DATE, cad.dt_end_interval))
            )
        ) AS dt_reference
    FROM
        datalake_cyber.contract_agency_distribution AS cad
    WHERE
        cad.creditor = 'QuintoAndar'
        AND cad.dt_end_interval IS NOT NULL
        AND cad.dt_start_interval <= cad.dt_end_interval
)
SELECT
  ei.id_contract,
  ei.id_agency,
  ei.main_agency_name,
  hcd.agency AS original_agency_distribution,
  ei.dt_reference
FROM expand_interval AS ei
  LEFT JOIN datalake_cyber_clean.contracts AS c
    ON ei.id_contract = c.id_contract_external
LEFT JOIN datalake_cyber_clean.history_contract_distribution As hcd
  ON c.id_contract = hcd.id_contract
    AND ei.dt_reference = hcd.ts_distribution
