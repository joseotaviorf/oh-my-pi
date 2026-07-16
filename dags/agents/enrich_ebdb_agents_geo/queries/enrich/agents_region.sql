WITH agent_region_hist AS (
  SELECT
    id_agent_data AS id_agent,
    id_region,
    rev_type,
    CASE 
        WHEN aud.rev_type = 2 THEN from_unixtime(ure.ts_revision/1000) 
        ELSE NULL 
    END AS ts_ended,
    FROM_UNIXTIME(ure.ts_revision/1000) AS ts_revision,
    CASE 
        WHEN aud.rev_type = 0 THEN from_unixtime(ure.ts_revision/1000)
        ELSE NULL
    END AS ts_started
  FROM
    datalake_ebdb_clean.agent_region_data_aud AS aud
  LEFT JOIN 
    datalake_ebdb_clean.user_revision_entity AS ure 
      ON aud.rev = ure.id 
)
SELECT
  arh.id_agent,
  arh.id_region,
  arh.rev_type,
  ar.region_code,
  arh.ts_ended,
  arh.ts_revision,
  arh.ts_started
FROM
  agent_region_hist arh
LEFT JOIN 
  datalake_gsheets_clean.auxiliary_region ar 
    ON arh.id_region = ar.id