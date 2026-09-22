WITH
talent_review_source AS (
  SELECT
    id_period_of_service,
    id_meeting,
    dt_committee_meeting,
    has_calibrated_rating,
    initial_criticality,
    initial_potential,
    initial_risk_of_loss,
    initial_readiness,
    calibrated_criticality,
    calibrated_potential,
    calibrated_risk_of_loss,
    calibrated_readiness,
    initial_numeric_criticality,
    initial_numeric_potential,
    initial_numeric_risk_of_loss,
    initial_numeric_readiness,
    calibrated_numeric_criticality,
    calibrated_numeric_potential,
    calibrated_numeric_risk_of_loss,
    calibrated_numeric_readiness,
    assignment_number,
    ts_created,
    ts_updated
  FROM
    datalake_performance.talent_review
  UNION ALL
  SELECT
    id_period_of_service,
    id_meeting,
    dt_committee_meeting,
    has_calibrated_rating,
    initial_criticality,
    initial_potential,
    initial_risk_of_loss,
    initial_readiness,
    calibrated_criticality,
    calibrated_potential,
    calibrated_risk_of_loss,
    calibrated_readiness,
    initial_numeric_criticality,
    initial_numeric_potential,
    initial_numeric_risk_of_loss,
    initial_numeric_readiness,
    calibrated_numeric_criticality,
    calibrated_numeric_potential,
    calibrated_numeric_risk_of_loss,
    calibrated_numeric_readiness,
    assignment_number,
    ts_created,
    ts_updated
  FROM
    datalake_people.talent_review_2026_h2
),
rating_change AS (
  SELECT
    id_period_of_service,
    id_meeting,
    dt_committee_meeting,
    calibrated_numeric_risk_of_loss 
      - LAG(calibrated_numeric_risk_of_loss) OVER 
        (PARTITION BY id_period_of_service ORDER BY dt_committee_meeting, id_meeting) 
    AS dif_risk_of_loss,
    calibrated_numeric_criticality 
      - LAG(calibrated_numeric_criticality) 
        OVER (PARTITION BY id_period_of_service ORDER BY dt_committee_meeting, id_meeting) 
    AS dif_criticality,
    calibrated_numeric_readiness 
      - LAG(calibrated_numeric_readiness) 
        OVER (PARTITION BY id_period_of_service ORDER BY dt_committee_meeting, id_meeting) 
    AS dif_readiness,
    calibrated_numeric_potential 
      - LAG(calibrated_numeric_potential) 
        OVER (PARTITION BY id_period_of_service ORDER BY dt_committee_meeting, id_meeting) 
    AS dif_potential
  FROM
    talent_review_source
  WHERE
    has_calibrated_rating = TRUE
),
talent_review_base AS (
SELECT
  MD5(CONCAT(tr.id_period_of_service, tr.id_meeting)) AS sk_talent_review,
  tr.id_period_of_service AS sk_assignment,
  tr.id_meeting AS sk_committee_meeting,
  COALESCE(DATE_FORMAT(tr.dt_committee_meeting, 'yyyyMMdd'), -1) AS sk_committee_meeting_date,
  MD5(CONCAT(
    dcm.meeting_type,
    CAST(dcm.meeting_year AS STRING),
    COALESCE(dcm.reference_period, '-1')
  )) AS sk_cycle_period,
  dcm.ts_meeting AS ts_committee_meeting,
  MD5(CONCAT(
    COALESCE(tr.initial_criticality, -1),
    COALESCE(tr.initial_potential, -1),
    COALESCE(tr.initial_risk_of_loss, -1),
    COALESCE(tr.initial_readiness, -1)
  )) AS sk_talent_rating_from_manager,
  MD5(CONCAT(
    COALESCE(tr.calibrated_criticality, -1),
    COALESCE(tr.calibrated_potential, -1),
    COALESCE(tr.calibrated_risk_of_loss, -1),
    COALESCE(tr.calibrated_readiness, -1)
  )) AS sk_talent_rating_from_calibration,
  MD5(CONCAT(
    CASE
      WHEN rc.dif_criticality IS NULL THEN '-1'
      WHEN rc.dif_criticality = 0 THEN 'Maintained'
      WHEN rc.dif_criticality < 0 THEN 'Decreased'
      WHEN rc.dif_criticality > 0 THEN 'Increased'
    END,
    CASE
      WHEN rc.dif_potential IS NULL THEN '-1'
      WHEN rc.dif_potential = 0 THEN 'Maintained'
      WHEN rc.dif_potential < 0 THEN 'Decreased'
      WHEN rc.dif_potential > 0 THEN 'Increased'
    END,
    CASE
      WHEN rc.dif_risk_of_loss IS NULL THEN '-1'
      WHEN rc.dif_risk_of_loss = 0 THEN 'Maintained'
      WHEN rc.dif_risk_of_loss < 0 THEN 'Decreased'
      WHEN rc.dif_risk_of_loss > 0 THEN 'Increased'
    END,
    CASE
      WHEN rc.dif_readiness IS NULL THEN '-1'
      WHEN rc.dif_readiness = 0 THEN 'Maintained'
      WHEN rc.dif_readiness < 0 THEN 'Decreased'
      WHEN rc.dif_readiness > 0 THEN 'Increased'
    END
  )) AS sk_talent_variation_period,
  MD5(CONCAT(
    CASE
      WHEN tr.initial_numeric_criticality IS NULL 
        OR tr.calibrated_numeric_criticality IS NULL 
        THEN -1
      WHEN tr.calibrated_numeric_criticality = tr.initial_numeric_criticality 
        THEN 'Maintained'
      WHEN tr.calibrated_numeric_criticality < tr.initial_numeric_criticality 
        THEN 'Decreased'
      WHEN tr.calibrated_numeric_criticality > tr.initial_numeric_criticality 
        THEN 'Increased'
    END,
    CASE
      WHEN tr.initial_numeric_potential IS NULL 
        OR tr.calibrated_numeric_potential IS NULL 
        THEN -1
      WHEN tr.calibrated_numeric_potential = tr.initial_numeric_potential 
        THEN 'Maintained'
      WHEN tr.calibrated_numeric_potential < tr.initial_numeric_potential 
        THEN 'Decreased'
      WHEN tr.calibrated_numeric_potential > tr.initial_numeric_potential 
        THEN 'Increased'
    END,
    CASE
      WHEN tr.initial_numeric_risk_of_loss IS NULL 
        OR tr.calibrated_numeric_risk_of_loss IS NULL 
        THEN -1
      WHEN tr.calibrated_numeric_risk_of_loss = tr.initial_numeric_risk_of_loss 
        THEN 'Maintained'
      WHEN tr.calibrated_numeric_risk_of_loss < tr.initial_numeric_risk_of_loss 
        THEN 'Decreased'
      WHEN tr.calibrated_numeric_risk_of_loss > tr.initial_numeric_risk_of_loss 
        THEN 'Increased'
    END,
    CASE
      WHEN tr.initial_numeric_readiness IS NULL 
        OR tr.calibrated_numeric_readiness IS NULL 
        THEN -1
      WHEN tr.calibrated_numeric_readiness = tr.initial_numeric_readiness 
        THEN 'Maintained'
      WHEN tr.calibrated_numeric_readiness < tr.initial_numeric_readiness 
        THEN 'Decreased'
      WHEN tr.calibrated_numeric_readiness > tr.initial_numeric_readiness 
        THEN 'Increased'
    END
  )) AS sk_talent_variation_calibration,
  im.person_number,
  tr.assignment_number,
  tr.initial_numeric_risk_of_loss AS numeric_risk_of_loss_from_manager,
  tr.calibrated_numeric_risk_of_loss AS numeric_risk_of_loss_from_calibration,
  tr.initial_numeric_criticality AS numeric_criticality_from_manager,
  tr.calibrated_numeric_criticality AS numeric_criticality_from_calibration,
  tr.initial_numeric_readiness AS numeric_readiness_from_manager,
  tr.calibrated_numeric_readiness AS numeric_readiness_from_calibration,
  tr.initial_numeric_potential AS numeric_potential_from_manager,
  tr.calibrated_numeric_potential AS numeric_potential_from_calibration,
  CASE
    WHEN tr.calibrated_numeric_criticality = 1 
      OR tr.calibrated_numeric_potential = 3
    THEN TRUE
    ELSE FALSE
  END AS is_regrettable_loss,
  tr.dt_committee_meeting = MAX(tr.dt_committee_meeting) OVER (PARTITION BY tr.id_period_of_service) AS is_last_cycle,
  tr.ts_created,
  tr.ts_updated,
  NOW() AS ts_load
FROM
  talent_review_source AS tr
INNER JOIN
  rating_change AS rc
    ON tr.id_period_of_service = rc.id_period_of_service 
    AND tr.id_meeting = rc.id_meeting
INNER JOIN
  datalake_people.identifier_mapping AS im
    ON im.id_period_of_service = tr.id_period_of_service
LEFT JOIN
  dw_performance.dim_committee_meeting AS dcm
    ON dcm.sk_meeting = tr.id_meeting
-- Official DW rows: completed calibrations only (flag defined in enrich talent_review).
WHERE
  tr.has_calibrated_rating = TRUE
),
with_in_cycle AS (
  SELECT
    sk_talent_review,
    sk_assignment,
    sk_committee_meeting,
    sk_committee_meeting_date,
    sk_cycle_period,
    sk_talent_rating_from_manager,
    sk_talent_rating_from_calibration,
    sk_talent_variation_period,
    sk_talent_variation_calibration,
    person_number,
    assignment_number,
    numeric_risk_of_loss_from_manager,
    numeric_risk_of_loss_from_calibration,
    numeric_criticality_from_manager,
    numeric_criticality_from_calibration,
    numeric_readiness_from_manager,
    numeric_readiness_from_calibration,
    numeric_potential_from_manager,
    numeric_potential_from_calibration,
    is_regrettable_loss,
    is_last_cycle,
    (
      ROW_NUMBER() OVER (
        PARTITION BY
          person_number,
          sk_cycle_period
        ORDER BY
          ts_committee_meeting DESC NULLS LAST,
          sk_committee_meeting DESC
      ) = 1
    ) AS is_latest_for_employee_in_cycle,
    ts_committee_meeting,
    ts_created,
    ts_updated,
    ts_load
  FROM
    talent_review_base
)
SELECT
  wic.sk_talent_review,
  wic.sk_assignment,
  wic.sk_committee_meeting,
  wic.sk_committee_meeting_date,
  wic.sk_cycle_period,
  wic.sk_talent_rating_from_manager,
  wic.sk_talent_rating_from_calibration,
  wic.sk_talent_variation_period,
  wic.sk_talent_variation_calibration,
  wic.person_number,
  wic.assignment_number,
  wic.numeric_risk_of_loss_from_manager,
  wic.numeric_risk_of_loss_from_calibration,
  wic.numeric_criticality_from_manager,
  wic.numeric_criticality_from_calibration,
  wic.numeric_readiness_from_manager,
  wic.numeric_readiness_from_calibration,
  wic.numeric_potential_from_manager,
  wic.numeric_potential_from_calibration,
  wic.is_regrettable_loss,
  wic.is_last_cycle,
  wic.is_latest_for_employee_in_cycle,
  (
    COALESCE(dcp.is_released, FALSE)
    AND wic.is_latest_for_employee_in_cycle
    AND ROW_NUMBER() OVER (
      PARTITION BY wic.person_number
      ORDER BY
        CASE
          WHEN COALESCE(dcp.is_released, FALSE)
            AND wic.is_latest_for_employee_in_cycle
          THEN 0
          ELSE 1
        END,
        wic.ts_committee_meeting DESC NULLS LAST,
        wic.sk_committee_meeting DESC
    ) = 1
  ) AS is_latest_for_employee,
  wic.ts_created,
  wic.ts_updated,
  wic.ts_load
FROM
  with_in_cycle AS wic
LEFT JOIN
  dw_performance.dim_cycle_period AS dcp
    ON dcp.sk_cycle_period = wic.sk_cycle_period
