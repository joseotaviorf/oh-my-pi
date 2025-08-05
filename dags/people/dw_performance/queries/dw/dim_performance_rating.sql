SELECT DISTINCT
  id_performance_rating_from_manager AS sk_performance_rating,
  COALESCE(description_behavior_from_manager, -1) AS behavior,
  COALESCE(description_impact_from_manager, -1) AS impact,
  COALESCE(description_leadership_from_manager, -1) AS leadership
FROM
  datalake_pin.performance_evaluation

UNION 

SELECT DISTINCT
  id_performance_rating_from_calibration AS sk_performance_rating,
  COALESCE(description_behavior_from_calibration, -1) AS behavior,
  COALESCE(description_impact_from_calibration, -1) AS impact,
  COALESCE(description_leadership_from_calibration, -1) AS leadership
FROM
  datalake_pin.performance_evaluation