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
  MD5(CONCAT(tr.id_period_of_service, tr.id_meeting)) AS sk_talent_review,
  tr.id_period_of_service AS sk_assignment,
  tr.id_meeting AS sk_committee_meeting,
  COALESCE(DATE_FORMAT(tr.dt_committee_meeting, 'yyyyMMdd'), -1) AS sk_committee_meeting_date,
  MD5(CONCAT(
    COALESCE(tr.id_criticality_rating_level_initial, -1),
    COALESCE(tr.id_potential_rating_level_initial, -1),
    COALESCE(tr.id_risk_loss_rating_level_initial, -1),
    COALESCE(tr.id_readiness_rating_level_initial, -1)
  )) AS sk_talent_rating_from_manager,
  MD5(CONCAT(
    COALESCE(tr.id_criticality_rating_level_calibrated, -1),
    COALESCE(tr.id_potential_rating_level_calibrated, -1),
    COALESCE(tr.id_risk_loss_rating_level_calibrated, -1),
    COALESCE(tr.id_readiness_rating_level_calibrated, -1)
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
  datalake_pin.talent_review AS tr
INNER JOIN
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