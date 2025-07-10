WITH 
possible_values AS (
  SELECT 'Increased' AS value
  UNION ALL
  SELECT 'Decreased'
  UNION ALL
  SELECT 'Maintained'
  UNION ALL
  SELECT '-1'
)

SELECT
  MD5(CONCAT(
    cri.value, 
    rea.value, 
    pot.value, 
    rol.value
  )) AS sk_talent_variation,
  cri.value AS criticality,
  rea.value AS readiness,
  pot.value AS potential,
  rol.value AS risk_of_loss
FROM
  possible_values AS cri
CROSS JOIN 
  possible_values AS rea
CROSS JOIN 
  possible_values AS pot
CROSS JOIN 
  possible_values AS rol