SELECT
  -- ids
  open.id_opening,
  open.id_job,
  open.id_application_hired,
  open.id_ta_responsible,
  open.id_close_reason,
  -- text
  open.code,
  COALESCE(
    open.internal_position_code_quinto_andar_sp,
    open.internal_position_code_quinto_andar_mg,
    open.internal_position_code_classifieds,
    open.internal_position_code_benvi_pt,
    open.internal_position_code_mlsp,
    open.internal_position_code_grupo_navent,
    open.internal_position_code_dridco,
    open.internal_position_code_one_loop,
    open.internal_position_code_dridco_mexico
  ) AS internal_position_code,
  COALESCE(
    open.internal_position_name_quinto_andar_sp,
    open.internal_position_name_quinto_andar_mg,
    open.internal_position_name_classifieds,
    open.internal_position_name_benvi_pt,
    open.internal_position_name_mlsp,
    open.internal_position_name_grupo_navent,
    open.internal_position_name_dridco,
    open.internal_position_name_one_loop,
    open.internal_position_name_soluser,
    open.internal_position_name_dridco_mexico
  ) AS internal_position_name,
  open.status,
  close.name AS close_reason,
  open.affirmative_focus,
  open.attention_notes,
  open.band,
  open.career_path,
  open.ta_responsible_name,
  open.ta_responsible_email,
  open.hiring_manager_email,
  open.cost_center_code,
  open.cost_center,
  open.company,
  open.neotribe,
  open.salary_table,
  open.overhead_or_capacity,
  open.recruitment_strategy,
  open.work_hours,
  open.workplace,
  open.question_can_ai_do_the_job,
  open.request_reason,
  open.request_justification,
  open.replacement_reason,
  open.person_replaced_position_name,
  open.person_replaced_band,
  open.person_replaced_email,
  open.monthly_salary_range_currency,
  open.plr_currency,
  open.rvv_currency,
  open.sop_currency,
  -- numeric
  open.equity_options_min,
  open.equity_options_max,
  open.monthly_salary_range_min,
  open.monthly_salary_range_max,
  open.plr,
  open.plr_salary_multiplier_latam,
  open.rvv,
  open.sop,
  -- boolean
  open.is_confidential,
  open.has_disabilities_pwd_person_replaced,
  open.is_dedicated_to_for_sale_team,
  -- dates
  open.dt_kickoff,
  -- timestamps
  open.ts_opened,
  open.ts_closed,
  open.ts_updated_at_oracle,
  NOW() AS ts_load,
  -- partitions
  YEAR(open.ts_load) AS year,
  MONTH(open.ts_load) AS month,
  DAY(open.ts_load) AS day

FROM
  datalake_greenhouse_v3_clean.openings AS open
LEFT JOIN
  datalake_greenhouse_v3_clean.close_reasons AS close
    ON open.id_close_reason = close.id_close_reason
