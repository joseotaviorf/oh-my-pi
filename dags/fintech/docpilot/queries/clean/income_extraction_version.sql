SELECT
  id_external,
  transaction_id AS id_transaction,
  end_transaction_id AS id_end_transaction,
  external_source,
  processing_result,
  documents_type,
  extracted_data,
  errors,
  operation_type,
  processing_result_mod,
  documents_type_mod,
  extracted_data_mod,
  errors_mod,
  ts_created,
  ts_updated,
  ts_created_mod,
  ts_updated_mod
FROM
    datalake_docpilot_raw.incomeextraction_version
