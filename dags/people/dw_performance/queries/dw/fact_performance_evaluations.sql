WITH
calibration_change AS (
  SELECT
    id_evaluation,
    section_name,
    CASE
        WHEN COALESCE(numeric_rating_from_calibration - numeric_rating_from_manager, -99) = -99 THEN '-1'
        WHEN numeric_rating_from_calibration - numeric_rating_from_manager = 0 THEN 'Maintained'
        WHEN numeric_rating_from_calibration - numeric_rating_from_manager < 0 THEN 'Decreased'
        WHEN numeric_rating_from_calibration - numeric_rating_from_manager > 0 THEN 'Increased'
    END AS calibration_adjustment
  FROM
    datalake_pin.performance_calibration
),
rating_change_over_time AS (
  SELECT
    id_evaluation,
    section_name,
    numeric_rating_from_calibration 
      - LAG(numeric_rating_from_calibration) OVER 
        (PARTITION BY id_period_of_service, section_name ORDER BY dt_evaluation_occurred) 
    AS calibrated_rating_diff_from_previous
  FROM
    datalake_pin.performance_calibration
)

SELECT
    pc.id_evaluation AS sk_evaluation,
    pc.id_period_of_service AS sk_assignment,
    pc.id_person AS sk_employee,
    DATE_FORMAT(pc.dt_evaluation_occurred, 'yyyyMMdd') AS sk_evaluation_date,
    MD5(CONCAT(
        MAX(pc.id_rating_level_from_manager) FILTER (WHERE pc.section_name = 'Behavior'),
        MAX(pc.id_rating_level_from_manager) FILTER (WHERE pc.section_name = 'Impact'),
        MAX(pc.id_rating_level_from_manager) FILTER (WHERE pc.section_name = 'Leadership')
    )) AS sk_performance_rating_from_manager,
    MD5(CONCAT(
        MAX(pc.id_rating_level_from_calibration) FILTER (WHERE pc.section_name = 'Behavior'),
        MAX(pc.id_rating_level_from_calibration) FILTER (WHERE pc.section_name = 'Impact'),
        MAX(pc.id_rating_level_from_calibration) FILTER (WHERE pc.section_name = 'Leadership')
    )) AS sk_performance_rating_from_calibration,
    MD5(CONCAT(
        CASE
            WHEN b_cot.calibrated_rating_diff_from_previous IS NULL THEN '-1'
            WHEN b_cot.calibrated_rating_diff_from_previous = 0 THEN 'Maintained'
            WHEN b_cot.calibrated_rating_diff_from_previous < 0 THEN 'Decreased'
            WHEN b_cot.calibrated_rating_diff_from_previous > 0 THEN 'Increased'
        END,
        CASE
            WHEN i_cot.calibrated_rating_diff_from_previous IS NULL THEN '-1'
            WHEN i_cot.calibrated_rating_diff_from_previous = 0 THEN 'Maintained'
            WHEN i_cot.calibrated_rating_diff_from_previous < 0 THEN 'Decreased'
            WHEN i_cot.calibrated_rating_diff_from_previous > 0 THEN 'Increased'
        END,  
        CASE
            WHEN l_cot.calibrated_rating_diff_from_previous IS NULL THEN '-1'
            WHEN l_cot.calibrated_rating_diff_from_previous = 0 THEN 'Maintained'
            WHEN l_cot.calibrated_rating_diff_from_previous < 0 THEN 'Decreased'
            WHEN l_cot.calibrated_rating_diff_from_previous > 0 THEN 'Increased'
        END
    )) AS sk_performance_variation_period,
    MD5(CONCAT(
        MAX(cc.calibration_adjustment) FILTER (WHERE cc.section_name = 'Behavior'),
        MAX(cc.calibration_adjustment) FILTER (WHERE cc.section_name = 'Impact'),
        MAX(cc.calibration_adjustment) FILTER (WHERE cc.section_name = 'Leadership')
    )) AS sk_performance_variation_calibration,
    pc.assignment_number,
    MAX(pc.numeric_rating_from_manager) FILTER (WHERE pc.section_name = 'Behavior') AS numeric_behavior_from_manager,
    MAX(pc.numeric_rating_from_calibration) FILTER (WHERE pc.section_name = 'Behavior') AS numeric_behavior_from_calibration,
    MAX(pc.numeric_rating_from_manager) FILTER (WHERE pc.section_name = 'Impact') AS numeric_impact_from_manager,
    MAX(pc.numeric_rating_from_calibration) FILTER (WHERE pc.section_name = 'Impact') AS numeric_impact_from_calibration,
    MAX(pc.numeric_rating_from_manager) FILTER (WHERE pc.section_name = 'Leadership') AS numeric_leadership_from_manager,
    MAX(pc.numeric_rating_from_calibration) FILTER (WHERE pc.section_name = 'Leadership') AS numeric_leadership_from_calibration,
    YEAR(pc.dt_performance_document_started) = MAX(YEAR(pc.dt_performance_document_started)) OVER (PARTITION BY pc.id_period_of_service) AS is_last_cycle,
    NOW() AS ts_load
FROM 
    datalake_pin.performance_calibration AS pc
LEFT JOIN 
    calibration_change AS cc 
        ON pc.id_evaluation = cc.id_evaluation
LEFT JOIN 
    rating_change_over_time AS b_cot
        ON pc.id_evaluation = b_cot.id_evaluation
        AND b_cot.section_name = 'Behavior'
LEFT JOIN 
    rating_change_over_time AS i_cot
        ON pc.id_evaluation = i_cot.id_evaluation
        AND i_cot.section_name = 'Impact'
LEFT JOIN 
    rating_change_over_time AS l_cot
        ON pc.id_evaluation = l_cot.id_evaluation
        AND l_cot.section_name = 'Leadership'
GROUP BY
    pc.id_evaluation,
    pc.id_period_of_service,
    pc.id_person,
    pc.dt_evaluation_occurred,
    pc.dt_performance_document_started,
    pc.assignment_number,
    l_cot.calibrated_rating_diff_from_previous,
    i_cot.calibrated_rating_diff_from_previous,
    b_cot.calibrated_rating_diff_from_previous
