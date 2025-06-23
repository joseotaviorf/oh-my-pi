SELECT
  elig_dpnt_id AS id_eligible_dependent,
  business_group_id AS id_business_group,
  elig_per_elctbl_chc_id AS id_eligible_per_electable_choice,
  per_in_ler_id AS id_period_in_life_event_reason,
  elig_per_id AS id_eligible_person,
  elig_per_opt_id AS id_eligible_person_option,
  dpnt_person_id AS id_dependent_person,
  CAST(request_id AS INT) AS id_request,
  rlnshp_cd AS relationship_code,
  created_by,
  last_updated_by AS updated_by,
  CAST(object_version_number AS INT) AS object_version_number,
  dpnt_inelig_flag = 'Y' AS is_dependent_ineligible,
  ovrdn_flag = 'Y' AS is_overridden,
  TO_DATE(elig_strt_dt) AS dt_eligibility_started,
  TO_DATE(elig_thru_dt) AS dt_eligibility_ended,
  TO_TIMESTAMP(create_dt) AS ts_record_created,
  TO_TIMESTAMP(last_update_date) AS ts_updated,
  TO_TIMESTAMP(creation_date) AS ts_created,
  TO_TIMESTAMP(program_update_date) AS ts_program_updated,
  NOW() AS ts_load
FROM
  datalake_pin_benefits_raw.ben_elig_dpnt
