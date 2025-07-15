SELECT DISTINCT
  MD5(CONCAT(
    COALESCE(behavior.rating_description_from_manager, -1), 
    COALESCE(impact.rating_description_from_manager, -1), 
    COALESCE(leadership.rating_description_from_manager, -1)
  )) AS sk_performance_rating,
  behavior.rating_description_from_manager AS behavior,
  impact.rating_description_from_manager AS impact,
  leadership.rating_description_from_manager AS leadership
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