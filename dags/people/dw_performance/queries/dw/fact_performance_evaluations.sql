WITH
rating_change_calibration AS (
  SELECT
    id_period_of_service,
    id_evaluation,
    section_name,
    CASE
        WHEN numeric_rating_from_calibration - numeric_rating_from_manager IS NULL THEN -1
        WHEN numeric_rating_from_calibration - numeric_rating_from_manager = 0 THEN 0
        WHEN numeric_rating_from_calibration - numeric_rating_from_manager < 0 THEN 1
        WHEN numeric_rating_from_calibration - numeric_rating_from_manager > 0 THEN 2
    END AS calibrarion_comparison
  FROM
    datalake_pin.performance_calibration
),
rating_change_period AS (
  SELECT
    id_period_of_service,
    id_evaluation,
    section_name,
    numeric_rating_from_calibration 
      - LAG(numeric_rating_from_calibration) OVER 
        (PARTITION BY section_name, id_period_of_service ORDER BY dt_evaluation_occurred) 
    AS dif_calibration
  FROM
    datalake_pin.performance_calibration
)

SELECT
    pc.id_evaluation AS sk_evaluation,
    pc.id_period_of_service AS sk_assignment,
    DATE_FORMAT(pc.dt_evaluation_occurred, 'yyyyMMdd') AS sk_evaluation_date,
    MAX(pc.id_rating_level_from_manager) FILTER (WHERE pc.section_name = 'Leadership') AS sk_leadership_initial,
    MAX(pc.id_rating_level_from_manager) FILTER (WHERE pc.section_name = 'Impact') AS sk_impact_initial,
    MAX(pc.id_rating_level_from_manager) FILTER (WHERE pc.section_name = 'Behavior') AS sk_behavior_initial,
    MAX(pc.id_rating_level_from_calibration) FILTER (WHERE pc.section_name = 'Leadership') AS sk_leadership_calibrated,
    MAX(pc.id_rating_level_from_calibration) FILTER (WHERE pc.section_name = 'Impact') AS sk_impact_calibrated,
    MAX(pc.id_rating_level_from_calibration) FILTER (WHERE pc.section_name = 'Behavior') AS sk_behavior_calibrated,
    MAX(rcc.calibrarion_comparison) FILTER (WHERE rcc.section_name = 'Leadership') AS sk_leadership_calibration_change,
    MAX(rcc.calibrarion_comparison) FILTER (WHERE rcc.section_name = 'Impact') AS sk_impact_calibration_change,
    MAX(rcc.calibrarion_comparison) FILTER (WHERE rcc.section_name = 'Behavior') AS sk_behavior_calibration_change,
    CASE
        WHEN lc.dif_calibration IS NULL THEN -1
        WHEN lc.dif_calibration = 0 THEN 0
        WHEN lc.dif_calibration < 0 THEN 1
        WHEN lc.dif_calibration > 0 THEN 2
    END AS sk_leadership_period_change,
    CASE
        WHEN ic.dif_calibration IS NULL THEN -1
        WHEN ic.dif_calibration = 0 THEN 0
        WHEN ic.dif_calibration < 0 THEN 1
        WHEN ic.dif_calibration > 0 THEN 2
    END AS sk_impact_period_change,    
    CASE
        WHEN bc.dif_calibration IS NULL THEN -1
        WHEN bc.dif_calibration = 0 THEN 0
        WHEN bc.dif_calibration < 0 THEN 1
        WHEN bc.dif_calibration > 0 THEN 2
    END AS sk_behavior_period_change,
    pc.assignment_number,
    MAX(pc.numeric_rating_from_manager) FILTER (WHERE pc.section_name = 'Leadership') AS initial_leadership_value,
    MAX(pc.numeric_rating_from_manager) FILTER (WHERE pc.section_name = 'Impact') AS initial_impact_value,
    MAX(pc.numeric_rating_from_manager) FILTER (WHERE pc.section_name = 'Behavior') AS initial_behavior_value,
    MAX(pc.numeric_rating_from_calibration) FILTER (WHERE pc.section_name = 'Leadership') AS calibrated_leadership_value,
    MAX(pc.numeric_rating_from_calibration) FILTER (WHERE pc.section_name = 'Impact') AS calibrated_impact_value,
    MAX(pc.numeric_rating_from_calibration) FILTER (WHERE pc.section_name = 'Behavior') AS calibrated_behavior_value,
    YEAR(pc.dt_performance_document_started) = MAX(YEAR(pc.dt_performance_document_started)) OVER (PARTITION BY pc.id_period_of_service) AS is_last_cycle,
    NOW() AS ts_load,
    YEAR(pc.dt_performance_document_started) AS year, 
    MONTH(pc.dt_performance_document_started) AS month, 
    MONTH(pc.dt_performance_document_started) AS day
FROM 
    datalake_pin.performance_calibration AS pc
LEFT JOIN 
    rating_change_calibration AS rcc 
        ON pc.id_evaluation = rcc.id_evaluation
LEFT JOIN 
    rating_change_period AS bc 
        ON pc.id_evaluation = bc.id_evaluation
        AND bc.section_name = 'Behavior'
LEFT JOIN 
    rating_change_period AS ic 
        ON pc.id_evaluation = ic.id_evaluation
        AND ic.section_name = 'Impact'
LEFT JOIN 
    rating_change_period AS lc 
        ON pc.id_evaluation = lc.id_evaluation
        AND lc.section_name = 'Leadership'
GROUP BY
    pc.id_evaluation,
    pc.id_period_of_service,
    pc.dt_evaluation_occurred,
    pc.dt_performance_document_started,
    pc.cycle,
    pc.assignment_number,
    lc.dif_calibration,
    ic.dif_calibration,
    bc.dif_calibration
