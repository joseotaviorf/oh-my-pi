WITH revised_agent_data_programs_aud AS (
    SELECT
      adp.id,
      adp.id_agent_data,
      adp.rev,
      adp.rev_type,
      adp.program,
      adp.is_eligible,
      IFNULL(LAG(adp.is_eligible) OVER(PARTITION BY adp.id ORDER BY adp.rev) != adp.is_eligible, true) AS mod_is_eligible,
      r.ts_revision
    FROM
      datalake_ebdb_clean.agent_data_programs_aud AS adp
    LEFT JOIN
      datalake_ebdb_user.user_revision_entity AS r
        ON r.id = adp.rev
    WHERE
      program = 'PREFERRED_PROPERTY_AGENT'
      AND DATE(r.ts_revision) <= DATE('{load_end_date}')
)
SELECT
  XXHASH64(id_agent_data, ts_revision) AS id_snapshot,
  id,
  id_agent_data AS id_agent,
  program,
  is_eligible,
  ts_revision AS ts_status_started,
  LEAD(ts_revision) OVER(PARTITION BY id ORDER BY rev) AS ts_status_ended
FROM
  revised_agent_data_programs_aud
WHERE
  mod_is_eligible = TRUE
  AND DATE(ts_revision) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
