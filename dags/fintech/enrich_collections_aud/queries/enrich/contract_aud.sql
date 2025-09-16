WITH terminations AS (
    SELECT
        id_contract,
        status,
        dt_vacancy,
        IF(status = 'DONE', DATE(ts_updated), NULL) AS dt_termination_finished
    FROM
        datalake_terminator_clean.termination
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_contract ORDER BY ts_created DESC) = 1
),
contract_analyst_annulment_date as (
    SELECT
      c_aud.id_contract,
      c_aud.id_house,
      c_aud.rev,
      row_number() OVER(PARTITION BY c_aud.id_contract order by ure.ts_revision) as row_number,
      c_aud.mod_dt_termination,
      c_aud.dt_termination,
      lag(c_aud.dt_termination) OVER(partition by c_aud.id_contract order by c_aud.rev) as dt_previous_termination,
      from_unixtime(ure.ts_revision/1000) AS ts_revision,
      coalesce(from_unixtime(ure.ts_revision/1000), c_aud.dt_termination) AS ts_analyst_annulment_input
    FROM datalake_ebdb_clean.contract_aud c_aud
    INNER JOIN datalake_ebdb_clean.user_revision_entity ure
      ON ure.id = c_aud.rev
    WHERE c_aud.mod_dt_termination
    QUALIFY ROW_NUMBER() over(partition by c_aud.id_contract order by ure.ts_revision) = 1
),
get_contract_by_month AS (
  SELECT
    id,
    imovel_id AS id_house,
    garantia AS guarantee_type,
    status,
    dataRescisao AS dt_termination,
    dataInicio AS dt_started,
    dataAssinado AS ts_signature,
    ts_database_transaction,
    ts_cdc_transaction AS ts_snapshot,
    year,
    month,
    day
  FROM datalake_ebdb_transactional.contrato
  WHERE MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
  c.id AS id_contract,
  ch.country_code,
  h.city,
  c.guarantee_type AS guarantee,
  c.status,
  c.dt_termination AS dt_termination_original,
  IF(t.status = 'DONE' AND c.dt_termination > DATE('2020-01-07'), t.dt_vacancy, c.dt_termination) AS dt_annulment,
  c.dt_started,
  c.ts_signature,
  CAST(aad.ts_analyst_annulment_input AS TIMESTAMP) AS ts_analyst_annulment_input,
  c.ts_database_transaction,
  c.ts_snapshot,
  c.year,
  c.month,
  c.day,
  NOW() AS ts_load
FROM get_contract_by_month AS c
INNER JOIN
  datalake_ebdb_country.house AS ch
    ON ch.id_house = c.id_house
LEFT JOIN
  terminations AS t
    ON t.id_contract = c.id
LEFT JOIN
  contract_analyst_annulment_date AS aad
    ON aad.id_contract = c.id
LEFT JOIN
  datalake_ebdb_listing.house AS h
    ON h.id = c.id_house
