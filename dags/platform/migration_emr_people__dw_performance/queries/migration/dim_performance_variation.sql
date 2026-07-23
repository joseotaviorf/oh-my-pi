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
    behavior.value, 
    impact.value, 
    leadership.value
  )) AS sk_performance_trend,
  behavior.value AS behavior,
  impact.value AS impact,
  leadership.value AS leadership
FROM
  possible_values AS behavior
CROSS JOIN 
  possible_values AS impact
CROSS JOIN 
  possible_values AS leadership
