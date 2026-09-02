SELECT
  id,
  credit_proposal_reference_id AS id_credit_proposal_reference,
  analyst_reference_id AS id_analyst_reference,
  uuid AS uuid_credit_proposal_crawler_job,
  crawler_type AS crawler_type_name,
  state AS state_name,
  failure_reason,
  failure_category,
  step_failure,
  step_section_failure,
  retry_count,
  fields_filled,
  version,
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_mortgage_management_service_raw.credit_proposal_crawler_job
