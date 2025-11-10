WITH
job_with_attributes AS (
  SELECT
    job.id_job,
    job.job_code,
    job.contribution_level,
    job.work_arrangement,
    job.target_sop_currency,
    job.weekly_hours,
    job.target_plr,
    job.target_plr_salary_multiplier,
    job.target_rvv,
    job.target_sop,
    job.target_hiring_sop,
    job.target_bonus_tech_usd,
    job.is_active,
    job.is_time_clocking_required,
    job.dt_effective_started,
    job.id_job_family,
    job.id_grade_ladder,
    job.id_set,
    job_tl.name AS job_name,
    job_family_tl.job_family_name,
    grade_tl.name AS band,
    grade_ladder_tl.name AS comp_ladder_directorate,
    set_id.set_name AS comp_ladder_business_unit,
    job_leg.brazilian_occupation_code,
    rate_val.mid_value AS salary_range_midpoint,
    rate_val.minimum_value AS salary_range_min,
    rate_val.maximum_value AS salary_range_max
  FROM
    datalake_pin_core_clean.job
  LEFT JOIN
    datalake_pin_core_clean.job_translation AS job_tl
      ON job.id_job = job_tl.id_job
      AND job_tl.language = 'PTB'
  LEFT JOIN
    datalake_pin_core_clean.job_family_translation AS job_family_tl
      ON job.id_job_family = job_family_tl.id_job_family
  LEFT JOIN
    datalake_pin_core_clean.grade_ladder_translation AS grade_ladder_tl
      ON job.id_grade_ladder = grade_ladder_tl.id_grade_ladder
  LEFT JOIN
    datalake_pin_core_clean.set_identifiers AS set_id
      ON job.id_set = set_id.id_set
      AND set_id.language = 'PTB'
  LEFT JOIN
    datalake_pin_core_clean.job_legislative AS job_leg
      ON job.id_job = job_leg.id_job
      AND job.dt_effective_started >= job_leg.dt_effective_started
      AND job.dt_effective_started < COALESCE(job_leg.dt_effective_ended, DATE('9999-12-31'))
  LEFT JOIN
    datalake_pin_core_clean.valid_grades
      ON job.id_job = valid_grades.id_job
      AND job.dt_effective_started >= valid_grades.dt_effective_started
      AND job.dt_effective_started < COALESCE(valid_grades.dt_effective_ended, DATE('9999-12-31'))
  LEFT JOIN
    datalake_pin_core_clean.grade_translation AS grade_tl
      ON valid_grades.id_grade = grade_tl.id_grade
  LEFT JOIN
    datalake_pin_core_clean.rates
      ON rates.id_grade_ladder = job.id_grade_ladder
      AND rates.rate_type = 'SALARY'
      AND job.dt_effective_started >= rates.dt_effective_started
      AND job.dt_effective_started < COALESCE(rates.dt_effective_ended, DATE('9999-12-31'))
  LEFT JOIN
    datalake_pin_core_clean.rate_values AS rate_val
      ON rate_val.id_rate = rates.id_rate
      AND rate_val.id_rate_object = valid_grades.id_grade
      AND job.dt_effective_started >= rate_val.dt_effective_started
      AND job.dt_effective_started < COALESCE(rate_val.dt_effective_ended, DATE('9999-12-31'))
  WHERE
    job.dt_effective_started <= CURRENT_DATE
  QUALIFY
    ROW_NUMBER() OVER (
      PARTITION BY job.id_job, job.dt_effective_started
      ORDER BY 
        job_tl.dt_effective_started DESC NULLS LAST,
        job_tl.object_version_number DESC NULLS LAST,
        job_family_tl.dt_effective_started DESC NULLS LAST,
        job_family_tl.object_version_number DESC NULLS LAST,
        grade_tl.dt_effective_started DESC NULLS LAST,
        grade_tl.object_version_number DESC NULLS LAST,
        grade_ladder_tl.dt_effective_started DESC NULLS LAST,
        grade_ladder_tl.object_version_number DESC NULLS LAST,
        set_id.ts_updated DESC NULLS LAST,
        job_leg.dt_effective_started DESC NULLS LAST,
        job_leg.object_version_number DESC NULLS LAST,
        valid_grades.dt_effective_started DESC NULLS LAST,
        valid_grades.object_version_number DESC NULLS LAST,
        rates.dt_effective_started DESC NULLS LAST,
        rates.object_version_number DESC NULLS LAST,
        rate_val.dt_effective_started DESC NULLS LAST,
        rate_val.object_version_number DESC NULLS LAST
    ) = 1
)
SELECT
  MD5(CONCAT_WS('|', CAST(id_job AS STRING), CAST(dt_effective_started AS STRING))) AS sk_job_version,
  id_job,
  job_code,
  ROW_NUMBER() OVER (PARTITION BY id_job ORDER BY dt_effective_started) AS version,
  job_name,
  job_family_name AS job_category,
  band,
  contribution_level AS career_track,
  comp_ladder_directorate,
  comp_ladder_business_unit,
  work_arrangement AS working_hours_regime,
  target_sop_currency,
  brazilian_occupation_code,
  weekly_hours AS workload,
  COALESCE(target_plr, 0) AS target_plr,
  COALESCE(target_plr_salary_multiplier, 0) AS target_plr_salary_multiplier,
  COALESCE(target_rvv, 0) AS target_rvv,
  COALESCE(target_sop, 0) AS target_sop,
  COALESCE(target_hiring_sop, 0) AS target_hiring_sop,
  COALESCE(target_bonus_tech_usd, 0) AS target_bonus_tech_usd,
  salary_range_midpoint,
  salary_range_min,
  salary_range_max,
  is_active,
  is_time_clocking_required AS has_clock_in,
  dt_effective_started,
  COALESCE(
    LEAD(dt_effective_started) OVER (
      PARTITION BY id_job
      ORDER BY dt_effective_started
    ) - INTERVAL '1 DAY',
    DATE('9999-12-31')
  ) AS dt_effective_ended,
  (
    LEAD(dt_effective_started) OVER (
      PARTITION BY id_job
      ORDER BY dt_effective_started
    ) IS NULL
  ) AS is_current,
  dt_effective_started AS dt_valid_from,
  COALESCE(
    LEAD(dt_effective_started) OVER (
      PARTITION BY id_job
      ORDER BY dt_effective_started
    ) - INTERVAL '1 DAY',
    DATE('9999-12-31')
  ) AS dt_valid_to,
  NOW() AS ts_load
FROM
  job_with_attributes
