WITH
eval AS (
  SELECT
    fpe.sk_performance_evaluation_manager_version,
    fpe.sk_performance_evaluation_self_version,
    fpe.sk_performance_evaluation_manager,
    fpe.sk_performance_evaluation_self,
    fpe.assignment_number,
    fpe.cycle_name,
    CAST(regexp_extract(fpe.cycle_name, '([0-9]{{4}})', 1) AS INT) AS cycle_year,
    fpe.behavior_self,
    fpe.impact_self,
    fpe.behavior_manager,
    fpe.impact_manager,
    fpe.numeric_behavior_self,
    fpe.numeric_impact_self,
    fpe.numeric_behavior_manager,
    fpe.numeric_impact_manager
  FROM
    dw_performance.fact_performance_evaluations AS fpe
),
assignment_to_person AS (
  SELECT
    SPLIT_PART(LOWER(TRIM(im.assignment_number)), '-', 1) AS assignment_key,
    im.person_number
  FROM
    datalake_people.identifier_mapping AS im
  WHERE
    im.is_person_latest_assignment = TRUE
  QUALIFY
    ROW_NUMBER() OVER (
      PARTITION BY SPLIT_PART(LOWER(TRIM(im.assignment_number)), '-', 1)
      ORDER BY
        im.person_number
    ) = 1
),
eval_with_person AS (
  SELECT
    e.*,
    atp.person_number
  FROM
    eval AS e
  INNER JOIN
    assignment_to_person AS atp
      ON SPLIT_PART(LOWER(TRIM(e.assignment_number)), '-', 1) = atp.assignment_key
),
goal_result_by_cycle AS (
  SELECT
    fga.person_number,
    fga.review_period_name,
    MAX(fga.goal_result) AS goal_result
  FROM
    dw_performance.fact_goal_achievements AS fga
  GROUP BY
    fga.person_number,
    fga.review_period_name
),
band_to_one_five AS (
  SELECT
    ep.*,
    CASE TRIM(ep.behavior_self)
      WHEN 'Outstanding' THEN 5
      WHEN 'Above expectations' THEN 4
      WHEN 'Meets expectations' THEN 3
      WHEN 'Partially misses expectations' THEN 2
      WHEN 'Insufficient' THEN 1
      ELSE NULL
    END AS behavior_rating_band_self,
    CASE TRIM(ep.behavior_manager)
      WHEN 'Outstanding' THEN 5
      WHEN 'Above expectations' THEN 4
      WHEN 'Meets expectations' THEN 3
      WHEN 'Partially misses expectations' THEN 2
      WHEN 'Insufficient' THEN 1
      ELSE NULL
    END AS behavior_rating_band_manager_evaluation,
    CASE TRIM(ep.impact_self)
      WHEN 'Outstanding' THEN 5
      WHEN 'Above expectations' THEN 4
      WHEN 'Meets expectations' THEN 3
      WHEN 'Partially misses expectations' THEN 2
      WHEN 'Insufficient' THEN 1
      ELSE NULL
    END AS impact_rating_band_self,
    CASE TRIM(ep.impact_manager)
      WHEN 'Outstanding' THEN 5
      WHEN 'Above expectations' THEN 4
      WHEN 'Meets expectations' THEN 3
      WHEN 'Partially misses expectations' THEN 2
      WHEN 'Insufficient' THEN 1
      ELSE NULL
    END AS impact_rating_band_manager_evaluation
  FROM
    eval_with_person AS ep
),
calibration_curr AS (
  SELECT
    fpc.person_number,
    dcm.meeting_year,
    CASE TRIM(fpc.calibrated_impact_description)
      WHEN 'Outstanding' THEN 5
      WHEN 'Above expectations' THEN 4
      WHEN 'Meets expectations' THEN 3
      WHEN 'Partially misses expectations' THEN 2
      WHEN 'Insufficient' THEN 1
      ELSE NULL
    END AS calibrated_impact_band,
    CASE TRIM(fpc.calibrated_behavior_description)
      WHEN 'Outstanding' THEN 5
      WHEN 'Above expectations' THEN 4
      WHEN 'Meets expectations' THEN 3
      WHEN 'Partially misses expectations' THEN 2
      WHEN 'Insufficient' THEN 1
      ELSE NULL
    END AS calibrated_behavior_band
  FROM
    dw_performance.fact_performance_calibrations AS fpc
  LEFT JOIN
    dw_performance.dim_committee_meeting AS dcm
      ON fpc.sk_committee_meeting = dcm.sk_meeting
),
calibration_prev AS (
  SELECT
    fpc.person_number,
    dcm.meeting_year,
    CASE TRIM(fpc.calibrated_impact_description)
      WHEN 'Outstanding' THEN 5
      WHEN 'Above expectations' THEN 4
      WHEN 'Meets expectations' THEN 3
      WHEN 'Partially misses expectations' THEN 2
      WHEN 'Insufficient' THEN 1
      ELSE NULL
    END AS calibrated_impact_band,
    CASE TRIM(fpc.calibrated_behavior_description)
      WHEN 'Outstanding' THEN 5
      WHEN 'Above expectations' THEN 4
      WHEN 'Meets expectations' THEN 3
      WHEN 'Partially misses expectations' THEN 2
      WHEN 'Insufficient' THEN 1
      ELSE NULL
    END AS calibrated_behavior_band
  FROM
    dw_performance.fact_performance_calibrations AS fpc
  LEFT JOIN
    dw_performance.dim_committee_meeting AS dcm
      ON fpc.sk_committee_meeting = dcm.sk_meeting
),
base AS (
  SELECT
    b.sk_performance_evaluation_manager_version,
    b.sk_performance_evaluation_self_version,
    b.sk_performance_evaluation_manager,
    b.sk_performance_evaluation_self,
    b.person_number,
    b.assignment_number,
    b.cycle_name,
    b.cycle_year,
    g.goal_result,
    b.behavior_rating_band_self,
    b.behavior_rating_band_manager_evaluation,
    b.impact_rating_band_self,
    b.impact_rating_band_manager_evaluation,
    COALESCE(cc.calibrated_impact_band, b.impact_rating_band_manager_evaluation)
      AS impact_rating_band_manager_resolved,
    COALESCE(cc.calibrated_behavior_band, b.behavior_rating_band_manager_evaluation)
      AS behavior_rating_band_manager_resolved,
    cp.calibrated_impact_band AS impact_rating_band_prior_performa_calibrated,
    cp.calibrated_behavior_band AS behavior_rating_band_prior_performa_calibrated
  FROM
    band_to_one_five AS b
  LEFT JOIN
    goal_result_by_cycle AS g
      ON g.person_number = b.person_number
      AND g.review_period_name = b.cycle_name
  LEFT JOIN
    calibration_curr AS cc
      ON cc.person_number = b.person_number
      AND b.cycle_year IS NOT NULL
      AND cc.meeting_year = b.cycle_year + 1
  LEFT JOIN
    calibration_prev AS cp
      ON cp.person_number = b.person_number
      AND b.cycle_year IS NOT NULL
      AND cp.meeting_year = b.cycle_year
),
flags AS (
  SELECT
    base.sk_performance_evaluation_manager_version,
    base.sk_performance_evaluation_self_version,
    base.sk_performance_evaluation_manager,
    base.sk_performance_evaluation_self,
    base.person_number,
    base.assignment_number,
    base.cycle_name,
    base.cycle_year,
    base.goal_result,
    base.impact_rating_band_self,
    base.behavior_rating_band_self,
    base.impact_rating_band_manager_evaluation,
    base.behavior_rating_band_manager_evaluation,
    base.impact_rating_band_manager_resolved,
    base.behavior_rating_band_manager_resolved,
    base.impact_rating_band_prior_performa_calibrated,
    base.behavior_rating_band_prior_performa_calibrated,
    CASE
      WHEN base.goal_result IS NULL OR base.impact_rating_band_manager_resolved IS NULL THEN FALSE
      WHEN base.goal_result >= 1.2 AND base.impact_rating_band_manager_resolved <= 3 THEN TRUE
      WHEN base.goal_result >= 1.1 AND base.goal_result < 1.2 AND base.impact_rating_band_manager_resolved <= 2 THEN TRUE
      WHEN base.goal_result >= 0.9 AND base.goal_result < 1.1
        AND (base.impact_rating_band_manager_resolved = 1 OR base.impact_rating_band_manager_resolved = 5)
        THEN TRUE
      WHEN base.goal_result >= 0.7 AND base.goal_result < 0.9 AND base.impact_rating_band_manager_resolved >= 4 THEN TRUE
      WHEN base.goal_result < 0.7 AND base.impact_rating_band_manager_resolved >= 3 THEN TRUE
      ELSE FALSE
    END AS is_smoke_goal_score_inconsistent_with_resolved_manager_impact_band,
    CASE
      WHEN base.impact_rating_band_manager_resolved IS NULL OR base.impact_rating_band_self IS NULL THEN FALSE
      WHEN ABS(base.impact_rating_band_manager_resolved - base.impact_rating_band_self) >= 2 THEN TRUE
      ELSE FALSE
    END AS is_smoke_gap_at_least_two_steps_impact_self_vs_manager_resolved,
    CASE
      WHEN base.behavior_rating_band_manager_resolved IS NULL OR base.behavior_rating_band_self IS NULL THEN FALSE
      WHEN ABS(base.behavior_rating_band_manager_resolved - base.behavior_rating_band_self) >= 2 THEN TRUE
      ELSE FALSE
    END AS is_smoke_gap_at_least_two_steps_behavior_self_vs_manager_resolved,
    CASE
      WHEN base.impact_rating_band_manager_resolved IS NULL
        OR base.impact_rating_band_prior_performa_calibrated IS NULL THEN FALSE
      WHEN ABS(
        base.impact_rating_band_manager_resolved - base.impact_rating_band_prior_performa_calibrated
      ) >= 2 THEN TRUE
      ELSE FALSE
    END AS is_smoke_gap_at_least_two_steps_impact_resolved_vs_prior_performa_calibrated,
    CASE
      WHEN base.behavior_rating_band_manager_resolved IS NULL
        OR base.behavior_rating_band_prior_performa_calibrated IS NULL THEN FALSE
      WHEN ABS(
        base.behavior_rating_band_manager_resolved - base.behavior_rating_band_prior_performa_calibrated
      ) >= 2 THEN TRUE
      ELSE FALSE
    END AS is_smoke_gap_at_least_two_steps_behavior_resolved_vs_prior_performa_calibrated
  FROM
    base
)
SELECT
  sk_performance_evaluation_manager_version,
  sk_performance_evaluation_self_version,
  sk_performance_evaluation_manager,
  sk_performance_evaluation_self,
  person_number,
  assignment_number,
  cycle_name,
  cycle_year,
  goal_result,
  impact_rating_band_self,
  behavior_rating_band_self,
  impact_rating_band_manager_evaluation,
  behavior_rating_band_manager_evaluation,
  impact_rating_band_manager_resolved,
  behavior_rating_band_manager_resolved,
  impact_rating_band_prior_performa_calibrated,
  behavior_rating_band_prior_performa_calibrated,
  is_smoke_goal_score_inconsistent_with_resolved_manager_impact_band,
  is_smoke_gap_at_least_two_steps_impact_self_vs_manager_resolved,
  is_smoke_gap_at_least_two_steps_behavior_self_vs_manager_resolved,
  is_smoke_gap_at_least_two_steps_impact_resolved_vs_prior_performa_calibrated,
  is_smoke_gap_at_least_two_steps_behavior_resolved_vs_prior_performa_calibrated,
  CAST(is_smoke_goal_score_inconsistent_with_resolved_manager_impact_band AS INT)
  + CAST(is_smoke_gap_at_least_two_steps_impact_self_vs_manager_resolved AS INT)
  + CAST(is_smoke_gap_at_least_two_steps_behavior_self_vs_manager_resolved AS INT)
  + CAST(is_smoke_gap_at_least_two_steps_impact_resolved_vs_prior_performa_calibrated AS INT)
  + CAST(is_smoke_gap_at_least_two_steps_behavior_resolved_vs_prior_performa_calibrated AS INT) AS num_smoke_flags_sd1_to_sd5,
  NOW() AS ts_load
FROM
  flags
