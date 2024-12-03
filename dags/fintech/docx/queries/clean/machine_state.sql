SELECT
  id AS id_machine_state,
  input_source_id AS id_input_source,
  context_external_id AS id_context_external,
  group_id AS id_group,
  scope_id AS id_scope,
  status,
  type,
  input_source_type,
  input_description,
  version,
  scope_type,
  active AS is_active,
  expires_at AS ts_expires,
  created_at AS ts_created,
  updated_at AS ts_updated
FROM
  datalake_docx_raw.machine_state
