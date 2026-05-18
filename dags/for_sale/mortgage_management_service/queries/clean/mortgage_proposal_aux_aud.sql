SELECT
  id,
  rev,
  revtype AS rev_type,
  revend AS rev_end,
  mortgage_intention_id AS id_mortgage_intention,
  mortgage_application_id AS id_mortgage_application,
  proposal_reference_id AS id_proposal_reference,
  pre_analysis_reference_id AS id_pre_analysis_reference,
  version,
  mortgage_intention_id_mod AS mod_id_mortgage_intention,
  mortgage_application_id_mod AS mod_id_mortgage_application,
  proposal_reference_id_mod AS mod_id_proposal_reference,
  pre_analysis_reference_id_mod AS mod_id_pre_analysis_reference,
  version_mod AS mod_version,
  created_at_mod AS mod_ts_created,
  updated_at_mod AS mod_ts_updated,
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_mortgage_management_service_raw.mortgage_proposal_aux_aud
