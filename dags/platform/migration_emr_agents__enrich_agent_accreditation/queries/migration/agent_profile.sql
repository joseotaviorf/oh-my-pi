WITH agent_type AS (
  SELECT
    aud.id_agent_data AS id_agent,
    aud.types,
    aud.rev_type,
    u.ts_revision AS ts_revision_started,
    LEAD(u.ts_revision) OVER (PARTITION BY aud.id_agent_data, aud.types ORDER BY u.ts_revision) AS ts_revision_ended,
    COALESCE(
      LEAD(u.ts_revision) OVER (PARTITION BY aud.id_agent_data, aud.types ORDER BY u.ts_revision),
      '{load_end_date}'
    ) AS ts_updated
  FROM datalake_ebdb_clean.agent_data_types_aud AS aud
  JOIN datalake_ebdb_user.user_revision_entity AS u
    ON u.id = aud.rev
  WHERE
    CAST(u.ts_revision AS DATE) <= CAST('{load_end_date}' AS DATE)
)
SELECT
  id_agent_profile,
  id_agent,
  profile,
  ts_revision_started,
  ts_revision_ended
FROM (
  SELECT
    XXHASH64(ag.id_agent, ag.types, ag.ts_revision_started) AS id_agent_profile,
    ag.id_agent,
    ag.types AS profile,
    ag.ts_revision_started,
    ag.ts_revision_ended,
    ROW_NUMBER() OVER (PARTITION BY XXHASH64(ag.id_agent, ag.types, ag.ts_revision_started) ORDER BY ag.ts_revision_started, COALESCE(ag.ts_revision_ended, ag.ts_updated) DESC) AS _w,
    ag.ts_updated
  FROM agent_type AS ag
  WHERE
    ag.rev_type <> 2
    AND CAST(ag.ts_updated AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
) AS _t
WHERE
  1 = _w