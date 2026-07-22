WITH last_type AS (
  SELECT
    id_agent_data,
    types,
    rev_type,
    rev
  FROM
    datalake_ebdb_clean.agent_data_types_aud
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_agent_data, types ORDER BY rev DESC) = 1
),
divergent_results AS (
  SELECT
    adt.id_agent_data,
    adt.types,
    lt.types AS last_type_in_aud
  FROM
    datalake_ebdb_clean.agent_data_types AS adt
  LEFT JOIN last_type AS lt
    ON adt.id_agent_data = lt.id_agent_data
    AND adt.types = lt.types
    AND COALESCE(lt.rev_type, 0) <> 2
  WHERE
    lt.types IS NULL
    AND adt.types = 'Visita'
)
SELECT
  dr.id_agent_data,
  dr.types,
  dr.last_type_in_aud,
  ad.agent_type,
  ad.is_active, 
  cu.id_agent IS NOT NULL AS is_ciq,
  ad.ts_created,
  CURRENT_DATE() AS dt_validated
FROM 
  divergent_results AS dr
LEFT JOIN
  datalake_ebdb_agents.ciq_agents AS cu
    ON dr.id_agent_data = cu.id_agent
LEFT JOIN
  datalake_ebdb_clean.agent_data AS ad
    ON dr.id_agent_data = ad.id
WHERE 
  ad.agent_type = 'CORRETOR_5A'