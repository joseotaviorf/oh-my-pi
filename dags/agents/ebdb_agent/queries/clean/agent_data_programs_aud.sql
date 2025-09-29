SELECT
  id,
  dados_agente_id AS id_agent_data,
  rev,
  revtype AS rev_type,
  program,
  BOOLEAN(eligible) AS is_eligible
FROM
  datalake_ebdb_raw.DadosAgente_programs_aud
