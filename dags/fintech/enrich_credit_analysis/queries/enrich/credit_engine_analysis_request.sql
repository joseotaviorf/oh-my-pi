SELECT
  ar.id AS id_analysis_request,
  ar.id_external,
  IF(ar.external_source = 'PROPOSAL', ar.id_external, NULL) AS id_proposal,
  ard.id_state_machine,
  ard.id_source,
  GET_JSON_OBJECT(ard.attributes, '$.credit_analysis_id') AS id_credit_analysis,
  GET_JSON_OBJECT(ard.attributes, '$.house_id') AS id_house,
  GET_JSON_OBJECT(ard.attributes, '$.offer_firestore_id') AS id_offer_firestore,
  GET_JSON_OBJECT(ard.attributes, '$.bypass') AS bypass,
  GET_JSON_OBJECT(ard.attributes, '$.score_5a') AS internal_score,
  GET_JSON_OBJECT(ard.attributes, '$.risk_category') AS risk_category,
  GET_JSON_OBJECT(ard.attributes, '$.documentation_analysis_type') AS documentation_policy,
  GET_JSON_OBJECT(ard.attributes, '$.category') AS category,
  GET_JSON_OBJECT(ard.attributes, '$.type') AS guarantee_type,
  GET_JSON_OBJECT(ard.attributes, '$.package_value') AS package_value,
  ar.result AS analysis_request_result,
  ar.business_context,
  ard.version,
  ard.source_entity,
  ar.ts_created AS ts_analysis_request_created,
  ard.ts_updated AS ts_analysis_request_updated
FROM
    datalake_sorting_hat_clean.analysis_request_data AS ard
  LEFT JOIN
    datalake_sorting_hat_clean.analysis_request AS ar
      ON ar.id = ard.id_analysis_request