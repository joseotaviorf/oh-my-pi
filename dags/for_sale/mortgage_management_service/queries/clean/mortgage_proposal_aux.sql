SELECT
  id,
  mortgage_intention_id AS id_mortgage_intention,
  mortgage_application_id AS id_mortgage_application,
  proposal_reference_id AS id_proposal_reference,
  pre_analysis_reference_id AS id_pre_analysis_reference,
  version,
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_mortgage_management_service_raw.mortgage_proposal_aux
