WITH
change_calculations AS (
  SELECT
    id_evaluation,
    id_period_of_service,
    dt_evaluation_occurred,
    CASE
        WHEN numeric_behavior_from_calibration IS NULL OR numeric_behavior_from_manager IS NULL THEN '-1'
        WHEN numeric_behavior_from_calibration > numeric_behavior_from_manager THEN 'Increased'
        WHEN numeric_behavior_from_calibration < numeric_behavior_from_manager THEN 'Decreased'
        ELSE 'Maintained'
    END AS behavior_calibration_adjustment,
    CASE
        WHEN numeric_impact_from_calibration IS NULL OR numeric_impact_from_manager IS NULL THEN '-1'
        WHEN numeric_impact_from_calibration > numeric_impact_from_manager THEN 'Increased'
        WHEN numeric_impact_from_calibration < numeric_impact_from_manager THEN 'Decreased'
        ELSE 'Maintained'
    END AS impact_calibration_adjustment,
    CASE
        WHEN numeric_leadership_from_calibration IS NULL OR numeric_leadership_from_manager IS NULL THEN '-1'
        WHEN numeric_leadership_from_calibration > numeric_leadership_from_manager THEN 'Increased'
        WHEN numeric_leadership_from_calibration < numeric_leadership_from_manager THEN 'Decreased'
        ELSE 'Maintained'
    END AS leadership_calibration_adjustment,
    numeric_behavior_from_calibration - LAG(numeric_behavior_from_calibration, 1, 0) OVER (PARTITION BY id_period_of_service ORDER BY dt_evaluation_occurred) AS behavior_rating_diff_from_previous,
    numeric_impact_from_calibration - LAG(numeric_impact_from_calibration, 1, 0) OVER (PARTITION BY id_period_of_service ORDER BY dt_evaluation_occurred) AS impact_rating_diff_from_previous,
    numeric_leadership_from_calibration - LAG(numeric_leadership_from_calibration, 1, 0) OVER (PARTITION BY id_period_of_service ORDER BY dt_evaluation_occurred) AS leadership_rating_diff_from_previous
    
  FROM
    datalake_pin.performance_evaluation
)

SELECT
    pc.id_evaluation AS sk_evaluation,
    pc.id_period_of_service AS sk_assignment,
    pc.id_person AS sk_employee,
    COALESCE(CAST(DATE_FORMAT(pc.dt_evaluation_occurred, 'yyyyMMdd') AS INT), -1) AS sk_evaluation_date,
    id_performance_rating_from_manager AS sk_performance_rating_from_manager,
    id_performance_rating_from_calibration AS sk_performance_rating_from_calibration,
    MD5(CONCAT(
        CASE 
            WHEN cc.behavior_rating_diff_from_previous > 0 THEN 'Increased' 
            WHEN cc.behavior_rating_diff_from_previous < 0 THEN 'Decreased' 
            ELSE 'Maintained' 
        END,
        CASE 
            WHEN cc.impact_rating_diff_from_previous > 0 THEN 'Increased' 
            WHEN cc.impact_rating_diff_from_previous < 0 THEN 'Decreased' 
            ELSE 'Maintained' 
        END,
        CASE 
            WHEN cc.leadership_rating_diff_from_previous > 0 THEN 'Increased' 
            WHEN cc.leadership_rating_diff_from_previous < 0 THEN 'Decreased' 
            ELSE 'Maintained' 
        END
    )) AS sk_performance_variation_period,
    MD5(CONCAT(
        cc.behavior_calibration_adjustment,
        cc.impact_calibration_adjustment,
        cc.leadership_calibration_adjustment
    )) AS sk_performance_variation_calibration,
    pc.assignment_number,
    pc.numeric_behavior_from_manager,
    pc.numeric_behavior_from_calibration,
    pc.numeric_impact_from_manager,
    pc.numeric_impact_from_calibration,
    pc.numeric_leadership_from_manager,
    pc.numeric_leadership_from_calibration,
    YEAR(pc.dt_performance_document_started) = MAX(YEAR(pc.dt_performance_document_started)) OVER (PARTITION BY pc.id_period_of_service) AS is_last_cycle,
    NOW() AS ts_load
FROM 
    datalake_pin.performance_evaluation AS pc
LEFT JOIN 
    change_calculations AS cc 
        ON pc.id_evaluation = cc.id_evaluation