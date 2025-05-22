SELECT
  CAST(id AS BIGINT) AS id_machine_state,
  CAST(input_source_id AS BIGINT) AS id_input_source,
  CAST(context_external_id AS BIGINT) AS id_context_external,
  rev,
  revtype AS rev_type,
  revend AS rev_end,
  status,
  type,
  input_source_type,
  input_description,
  version,
  active AS is_active
FROM
  datalake_docx_raw.machine_state_aud
