WITH 
jobs_with_parsed_openings AS (
  SELECT
    *,
    FROM_JSON(
      job.openings,
      'ARRAY<STRUCT<
          id: BIGINT, 
          application_id: BIGINT, 
          opening_id: STRING, 
          status: STRING, 
          opened_at: STRING, 
          closed_at: STRING,
          close_reason: STRUCT<id: BIGINT, name: STRING>,
          keyed_custom_fields: STRUCT<
              ta_responsible: STRUCT<value: STRUCT<user_id: BIGINT, name: STRING, email: STRING>>,
              what_is_the_job_id_in_budget_: STRUCT<value: STRING>,
              internal_position_name___quinto_andar_sp: STRUCT<external_id: STRING, value: STRING>,
              internal_position_name___quinto_andar_mg: STRUCT<external_id: STRING, value: STRING>,
              internal_position_name___classifieds: STRUCT<external_id: STRING, value: STRING>,
              internal_position_name___benvi_pt: STRUCT<external_id: STRING, value: STRING>,
              internal_position_name___mlsp: STRUCT<external_id: STRING, value: STRING>,
              affirmative_focus: STRUCT<value: STRING>,
              attention: STRUCT<value: STRING>,
              band: STRUCT<value: STRING>,
              career_path: STRUCT<value: STRING>,
              headcount_hiring_manager_e_mail: STRUCT<value: STRING>,
              cost_center: STRUCT<external_id: STRING, value: STRING>,
              company: STRUCT<value: STRING>,
              neotribe: STRUCT<value: STRING>,
              salary_scale: STRUCT<value: STRING>,
              overhead_or_capacity: STRUCT<value: STRING>,
              recruitment_strategy: STRUCT<value: STRING>,
              work_hours: STRUCT<value: STRING>,
              workplace: STRUCT<value: STRING>,
              can_ai_do_the_job___please_explain_: STRUCT<value: STRING>,
              reason_for_the_position_request: STRUCT<value: STRING>,
              what_is_the_justification_for_opening_this_position_: STRUCT<value: STRING>,
              what_is_the_replacement_reason_: STRUCT<value: STRING>,
              name_of_the_position___level_of_the_position_that_is_being_replaced_opening_1755793581_1519: STRUCT<value: STRING>,
              band_of_the_person_being_replaced_opening_1755793711_165607: STRUCT<value: STRING>,
              email_of_the_person_being_replaced_: STRUCT<value: STRING>,
              monthly_salary_range: STRUCT<value: STRUCT<unit: STRING, min_value: STRING, max_value: STRING>>,
              plr: STRUCT<value: STRUCT<unit: STRING, value: STRING>>,
              rvv: STRUCT<value: STRUCT<unit: STRING, value: STRING>>,
              sop: STRUCT<value: STRUCT<unit: STRING, value: STRING>>,
              equity_options_approval_exception_range: STRUCT<value: STRUCT<min_value: STRING, max_value: STRING>>,
              plr_latam: STRUCT<value: STRING>,
              person_with_disabilties_: STRUCT<value: STRING>,
              will_this_position_be_100__dedicated_to_the_for_sale_team_: STRUCT<value: STRING>,
              updated_at_oic: STRUCT<value: STRING>,
              confidentiality_flag: STRUCT<value: STRING>,
              kickoff_date: STRUCT<value: STRING>
          >
      >>'
    ) AS openings_array
  FROM
    datalake_greenhouse_clean.jobs AS job
)

SELECT
  -- ids
  open.id,
  job.id AS id_job,
  open.application_id AS id_application_hired,
  open.keyed_custom_fields.ta_responsible.value.user_id AS id_ta_responsible,
  open.close_reason.id AS id_close_reason,
  -- text
  open.opening_id AS code,
  COALESCE(
    open.keyed_custom_fields.internal_position_name___quinto_andar_sp.external_id,
    open.keyed_custom_fields.internal_position_name___quinto_andar_mg.external_id,
    open.keyed_custom_fields.internal_position_name___classifieds.external_id,
    open.keyed_custom_fields.internal_position_name___benvi_pt.external_id,
    open.keyed_custom_fields.internal_position_name___mlsp.external_id
  ) AS internal_position_code,
  COALESCE(
    open.keyed_custom_fields.internal_position_name___quinto_andar_sp.value,
    open.keyed_custom_fields.internal_position_name___quinto_andar_mg.value,
    open.keyed_custom_fields.internal_position_name___classifieds.value,
    open.keyed_custom_fields.internal_position_name___benvi_pt.value,
    open.keyed_custom_fields.internal_position_name___mlsp.value
  ) AS internal_position_name,
  open.status,
  open.close_reason.name AS close_reason,
  open.keyed_custom_fields.affirmative_focus.value AS affirmative_focus,
  open.keyed_custom_fields.attention.value AS attention_notes,
  open.keyed_custom_fields.band.value AS band,
  open.keyed_custom_fields.career_path.value AS career_path,
  open.keyed_custom_fields.ta_responsible.value.name AS ta_responsible_name,
  open.keyed_custom_fields.ta_responsible.value.email AS ta_responsible_email,
  open.keyed_custom_fields.headcount_hiring_manager_e_mail.value AS hiring_manager_email,
  open.keyed_custom_fields.cost_center.external_id AS cost_center_code,
  open.keyed_custom_fields.cost_center.value AS cost_center,
  open.keyed_custom_fields.company.value AS company,
  open.keyed_custom_fields.neotribe.value AS neotribe,
  open.keyed_custom_fields.salary_scale.value AS salary_table,
  open.keyed_custom_fields.overhead_or_capacity.value AS overhead_or_capacity,
  open.keyed_custom_fields.recruitment_strategy.value AS recruitment_strategy,
  open.keyed_custom_fields.work_hours.value AS work_hours,
  open.keyed_custom_fields.workplace.value AS workplace,
  open.keyed_custom_fields.can_ai_do_the_job___please_explain_.value AS question_can_ai_do_the_job,
  open.keyed_custom_fields.reason_for_the_position_request.value AS request_reason,
  open.keyed_custom_fields.what_is_the_justification_for_opening_this_position_.value AS request_justification,
  open.keyed_custom_fields.what_is_the_replacement_reason_.value AS replacement_reason,
  open.keyed_custom_fields.name_of_the_position___level_of_the_position_that_is_being_replaced_opening_1755793581_1519.value AS person_replaced_position_name,
  open.keyed_custom_fields.band_of_the_person_being_replaced_opening_1755793711_165607.value AS person_replaced_band,
  open.keyed_custom_fields.email_of_the_person_being_replaced_.value AS person_replaced_email,
  open.keyed_custom_fields.monthly_salary_range.value.unit AS monthly_salary_range_currency,
  open.keyed_custom_fields.plr.value.unit AS plr_currency,
  open.keyed_custom_fields.rvv.value.unit AS rvv_currency,
  open.keyed_custom_fields.sop.value.unit AS sop_currency,
  -- numeric
  CAST(open.keyed_custom_fields.equity_options_approval_exception_range.value.min_value AS DECIMAL(10, 2)) AS equity_options_min,
  CAST(open.keyed_custom_fields.equity_options_approval_exception_range.value.max_value AS DECIMAL(10, 2)) AS equity_options_max,
  CAST(open.keyed_custom_fields.monthly_salary_range.value.min_value AS DECIMAL(10, 2)) AS monthly_salary_range_min,
  CAST(open.keyed_custom_fields.monthly_salary_range.value.max_value AS DECIMAL(10, 2)) AS monthly_salary_range_max,
  CAST(open.keyed_custom_fields.plr.value.value AS DECIMAL(10, 2)) AS plr,
  CAST(open.keyed_custom_fields.plr_latam.value AS DECIMAL(10, 2)) AS plr_salary_multiplier_latam,
  CAST(open.keyed_custom_fields.rvv.value.value AS DECIMAL(10, 2)) AS rvv,
  CAST(open.keyed_custom_fields.sop.value.value AS DECIMAL(10, 2)) AS sop,
  -- boolean
  CASE
    WHEN open.keyed_custom_fields.confidentiality_flag.value = 'Confidential' THEN TRUE
    ELSE FALSE
  END AS is_confidential,
  CAST(open.keyed_custom_fields.person_with_disabilties_.value AS BOOLEAN) AS has_disabilities_pwd_person_replaced,
  CASE
    WHEN open.keyed_custom_fields.will_this_position_be_100__dedicated_to_the_for_sale_team_.value = 'Yes' THEN True
    WHEN open.keyed_custom_fields.will_this_position_be_100__dedicated_to_the_for_sale_team_.value = 'No' THEN False
  END AS is_dedicated_to_for_sale_team,
  -- timestamps
  CAST(open.keyed_custom_fields.kickoff_date.value AS DATE) AS dt_kickoff,
  CAST(open.opened_at AS TIMESTAMP) AS ts_opened,
  CAST(open.closed_at AS TIMESTAMP) AS ts_closed,
  CAST(open.keyed_custom_fields.updated_at_oic.value AS TIMESTAMP) AS ts_updated_at_oracle,
  NOW() AS ts_load,
  -- partitions
  YEAR(open.opened_at) AS year,
  MONTH(open.opened_at) AS month,
  DAY(open.opened_at) AS day

FROM
  jobs_with_parsed_openings AS job
LATERAL VIEW
  EXPLODE(job.openings_array) AS open