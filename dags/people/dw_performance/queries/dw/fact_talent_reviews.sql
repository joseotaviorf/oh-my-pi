WITH
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
    datalake_pin.talent_review
)

SELECT
  MD5(tr.id_period_of_service, tr.id_meeting) AS sk_talent_review,
  tr.id_period_of_service AS sk_assignment,
  tr.id_meeting AS sk_committee_meeting,
  COALESCE(DATE_FORMAT(tr.dt_committee_meeting, 'yyyyMMdd'), -1) AS sk_committee_meeting_date,
  COALESCE(tr.id_risk_loss_rating_level_calibrated, -1) AS sk_rating_level_risk_of_loss_calibrated,
  COALESCE(tr.id_criticality_rating_level_calibrated, -1) AS sk_rating_level_criticality_calibrated,
  COALESCE(tr.id_readiness_rating_level_calibrated, -1) AS sk_rating_level_readiness_calibrated,
  COALESCE(tr.id_potential_rating_level_calibrated, -1) AS sk_rating_level_potential_calibrated,
  COALESCE(tr.id_risk_loss_rating_level_initial, -1) AS sk_rating_level_risk_of_loss_initial,
  COALESCE(tr.id_criticality_rating_level_initial, -1) AS sk_rating_level_criticality_initial,
  COALESCE(tr.id_readiness_rating_level_initial, -1) AS sk_rating_level_readiness_initial,
  COALESCE(tr.id_potential_rating_level_initial, -1) AS sk_rating_level_potential_initial,
  CASE
    WHEN rc.dif_risk_of_loss IS NULL THEN -1
    WHEN rc.dif_risk_of_loss = 0 THEN 0
    WHEN rc.dif_risk_of_loss < 0 THEN 1
    WHEN rc.dif_risk_of_loss > 0 THEN 2
  END AS sk_risk_of_loss_period_change,
  CASE
    WHEN rc.dif_criticality IS NULL THEN -1
    WHEN rc.dif_criticality = 0 THEN 0
    WHEN rc.dif_criticality < 0 THEN 1
    WHEN rc.dif_criticality > 0 THEN 2
  END AS sk_criticality_period_change,
  CASE
    WHEN rc.dif_readiness IS NULL THEN -1
    WHEN rc.dif_readiness = 0 THEN 0
    WHEN rc.dif_readiness < 0 THEN 1
    WHEN rc.dif_readiness > 0 THEN 2
  END AS sk_readiness_period_change,
  CASE
    WHEN rc.dif_potential IS NULL THEN -1
    WHEN rc.dif_potential = 0 THEN 0
    WHEN rc.dif_potential < 0 THEN 1
    WHEN rc.dif_potential > 0 THEN 2
  END AS sk_potential_period_change,
  CASE
    WHEN tr.initial_numeric_risk_of_loss IS NULL 
      OR tr.calibrated_numeric_risk_of_loss IS NULL 
    THEN -1
    WHEN tr.calibrated_numeric_risk_of_loss = tr.initial_numeric_risk_of_loss 
    THEN 0
    WHEN tr.calibrated_numeric_risk_of_loss < tr.initial_numeric_risk_of_loss 
    THEN 1
    WHEN tr.calibrated_numeric_risk_of_loss > tr.initial_numeric_risk_of_loss 
    THEN 2
  END AS sk_risk_of_loss_calibration_change,
  CASE
    WHEN tr.initial_numeric_criticality IS NULL 
      OR tr.calibrated_numeric_criticality IS NULL 
    THEN -1
    WHEN tr.calibrated_numeric_criticality = tr.initial_numeric_criticality 
    THEN 0
    WHEN tr.calibrated_numeric_criticality < tr.initial_numeric_criticality 
    THEN 1
    WHEN tr.calibrated_numeric_criticality > tr.initial_numeric_criticality 
    THEN 2
  END AS sk_criticality_calibration_change,
  CASE
    WHEN tr.initial_numeric_readiness IS NULL 
      OR tr.calibrated_numeric_readiness IS NULL 
    THEN -1
    WHEN tr.calibrated_numeric_readiness = tr.initial_numeric_readiness 
    THEN 0
    WHEN tr.calibrated_numeric_readiness < tr.initial_numeric_readiness 
    THEN 1
    WHEN tr.calibrated_numeric_readiness > tr.initial_numeric_readiness 
    THEN 2
  END AS sk_readiness_calibration_change,  
  CASE
    WHEN tr.initial_numeric_potential IS NULL 
      OR tr.calibrated_numeric_potential IS NULL 
    THEN -1
    WHEN tr.calibrated_numeric_potential = tr.initial_numeric_potential 
    THEN 0
    WHEN tr.calibrated_numeric_potential < tr.initial_numeric_potential 
    THEN 1
    WHEN tr.calibrated_numeric_potential > tr.initial_numeric_potential 
    THEN 2
  END AS sk_potential_calibration_change,  
  tr.assignment_number,
  tr.initial_numeric_risk_of_loss AS initial_risk_of_loss_value,
  tr.calibrated_numeric_risk_of_loss AS calibrated_risk_of_loss_value,
  tr.initial_numeric_criticality AS initial_criticality_value,
  tr.calibrated_numeric_criticality AS calibrated_criticality_value,
  tr.initial_numeric_readiness AS initial_readiness_value,
  tr.calibrated_numeric_readiness AS calibrated_readiness_value,
  tr.initial_numeric_potential AS initial_potential_value,
  tr.calibrated_numeric_potential AS calibrated_potential_value,
  CASE
    WHEN tr.calibrated_numeric_criticality = 1 
      OR tr.calibrated_numeric_potential = 3
    THEN TRUE
    ELSE FALSE
  END AS is_regrettable_loss,
  tr.ts_initial_risk_of_loss_created,
  tr.ts_initial_risk_of_loss_updated,
  tr.ts_initial_criticality_created,
  tr.ts_initial_criticality_updated,
  tr.ts_initial_readiness_created,
  tr.ts_initial_readiness_updated,
  tr.ts_initial_potential_created,
  tr.ts_initial_potential_updated,
  NOW() AS ts_load
FROM
  datalake_pin.talent_review AS tr
LEFT JOIN
  rating_change AS rc
    ON tr.id_period_of_service = rc.id_period_of_service 
    AND tr.id_meeting = rc.id_meeting
WHERE 
  COALESCE(
    tr.id_risk_loss_rating_level_calibrated,
    tr.id_criticality_rating_level_calibrated,
    tr.id_readiness_rating_level_calibrated,
    tr.id_potential_rating_level_calibrated,
    tr.id_risk_loss_rating_level_initial,
    tr.id_criticality_rating_level_initial,
    tr.id_readiness_rating_level_initial,
    tr.id_potential_rating_level_initial
  ) IS NOT NULL