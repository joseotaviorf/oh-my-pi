WITH json_parsed AS (
  SELECT
    id,
    analysis_request_id as id_analysis_request,
    subject_id as id_subject,
    status,
    subject_type,
    type,
    is_current_machine,
    machine_version,
    context,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    FROM_JSON(
      context,
      'proposal_id INT, risk_category STRING'
    ) AS parsed_json
  FROM
    datalake_sorting_hat_raw.analysismachine
)

SELECT
  id,
  id_analysis_request,
  parsed_json.proposal_id AS id_proposal,
  id_subject,
  status,
  subject_type,
  type,
  is_current_machine,
  machine_version,
  context,
  parsed_json.risk_category,
  ts_created,
  ts_updated
FROM
  json_parsed
