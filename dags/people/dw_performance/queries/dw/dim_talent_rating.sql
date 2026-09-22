WITH
talent_review AS (
  SELECT
    calibrated_criticality,
    calibrated_potential,
    calibrated_risk_of_loss,
    calibrated_readiness
  FROM
    datalake_performance.talent_review
  UNION ALL
  SELECT
    calibrated_criticality,
    calibrated_potential,
    calibrated_risk_of_loss,
    calibrated_readiness
  FROM
    datalake_people.talent_review_2026_h2
)
SELECT DISTINCT
  MD5(CONCAT(
    COALESCE(calibrated_criticality, '-1'),
    COALESCE(calibrated_potential, '-1'),
    COALESCE(calibrated_risk_of_loss, '-1'),
    COALESCE(calibrated_readiness, '-1')
  )) AS sk_talent_rating,
  calibrated_criticality AS criticality,
  calibrated_readiness AS readiness,
  calibrated_potential AS potential,
  calibrated_risk_of_loss AS risk_of_loss
FROM
  talent_review
