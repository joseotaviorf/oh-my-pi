SELECT DISTINCT
  MD5(CONCAT(
    behavior.rating_description_from_calibration, 
    impact.rating_description_from_calibration, 
    leadership.rating_description_from_calibration
  )) AS sk_performance_rating,
  behavior.rating_description_from_calibration AS behavior,
  impact.rating_description_from_calibration AS impact,
  leadership.rating_description_from_calibration AS leadership
FROM
  datalake_pin.performance_calibration AS behavior
CROSS JOIN 
  datalake_pin.performance_calibration AS impact
CROSS JOIN 
  datalake_pin.performance_calibration AS leadership
WHERE
  behavior.section_name = 'Behavior'
  AND impact.section_name = 'Impact'
  AND leadership.section_name = 'Leadership'
