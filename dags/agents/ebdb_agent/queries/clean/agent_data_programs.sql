SELECT
  id,
  dados_agente_id AS id_agent_data,
  program,
  BOOLEAN(eligible) AS is_eligible,
  created_at AS ts_created,
  updated_at AS ts_updated
FROM
  datalake_ebdb_raw.DadosAgente_programs
