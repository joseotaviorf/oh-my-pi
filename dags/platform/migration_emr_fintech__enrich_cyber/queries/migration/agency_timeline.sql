WITH expand_interval AS (
  SELECT
    id_contract,
    id_agency,
    main_agency_name,
    juridical_agency,
    conventional_agency,
    agencies_name_group,
    EXPLODE(
      SEQUENCE(
        dt_start_interval,
        GREATEST(
          dt_start_interval,
          IF(dt_end_interval = LAST_DAY(CURRENT_DATE), CURRENT_DATE, dt_end_interval)
        )
      )
    ) AS dt_reference
  FROM datalake_cyber.contract_agency_distribution
  WHERE
    creditor = 'QuintoAndar'
    AND NOT dt_end_interval IS NULL
    AND dt_start_interval <= dt_end_interval
), contract_distribution AS (
  SELECT
    id_contract,
    agency,
    dt_distribution
  FROM (
    SELECT
      c.id_contract_external AS id_contract,
      hcd.agency,
      CAST(hcd.ts_distribution AS DATE) AS dt_distribution,
      ROW_NUMBER() OVER (PARTITION BY c.id_contract_external, hcd.ts_distribution ORDER BY hcd.ts_redistribution, c.id_contract_external DESC) AS _w,
      c.id_contract_external,
      hcd.ts_distribution,
      hcd.ts_redistribution
    FROM datalake_cyber_clean.history_contract_distribution AS hcd
    LEFT JOIN datalake_cyber_clean.contracts AS c
      ON hcd.id_contract = c.id_contract
  ) AS _t
  WHERE
    _w = 1
)
SELECT
  ei.id_contract,
  ei.id_agency,
  ei.main_agency_name,
  ei.juridical_agency,
  ei.conventional_agency,
  ei.agencies_name_group,
  cd.agency AS original_agency_distribution,
  ei.dt_reference
FROM expand_interval AS ei
LEFT JOIN contract_distribution AS cd
  ON cd.id_contract = ei.id_contract AND ei.dt_reference = cd.dt_distribution
