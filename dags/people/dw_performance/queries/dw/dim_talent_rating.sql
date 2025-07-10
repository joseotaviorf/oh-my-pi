WITH
criticality AS (
  SELECT DISTINCT 
    calibrated_criticality AS criticality
  FROM 
    datalake_pin.talent_review
),
readiness AS (
  SELECT DISTINCT 
    calibrated_readiness AS readiness
  FROM 
    datalake_pin.talent_review
),
potential AS (
  SELECT DISTINCT 
    calibrated_potential AS potential
  FROM 
    datalake_pin.talent_review
),
risk_of_loss AS (
  SELECT DISTINCT 
    calibrated_risk_of_loss AS risk_of_loss
  FROM 
    datalake_pin.talent_review
)

SELECT
  MD5(CONCAT(
    cri.criticality, 
    rea.readiness, 
    pot.potential, 
    rol.risk_of_loss
  )) AS sk_talent_rating,
  cri.criticality,
  rea.readiness,
  pot.potential,
  rol.risk_of_loss
FROM
  criticality AS cri
CROSS JOIN 
  readiness AS rea
CROSS JOIN 
  potential AS pot
CROSS JOIN 
  risk_of_loss AS rol