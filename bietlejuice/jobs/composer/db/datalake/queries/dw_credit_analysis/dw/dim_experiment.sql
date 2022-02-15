SELECT
    id AS id_experiment,
    name AS experiment_name,
    description AS experiment_description,
    IF(ts_started IS NOT NULL AND ts_ended IS NULL, TRUE, FALSE) AS is_experiment_running,
    CASE 
        WHEN ts_started IS NOT NULL AND (ts_ended IS NULL OR ts_ended >= CURRENT_DATE() - INTERVAL 1 MONTH) THEN TRUE
            ELSE FALSE 
    END AS has_experiment_ran_last_month,
    CASE 
        WHEN ts_started IS NOT NULL AND (ts_ended IS NULL OR ts_ended >= CURRENT_DATE() - INTERVAL 3 MONTH) THEN TRUE
            ELSE FALSE 
    END AS has_experiment_ran_last_3_months,
    CASE 
        WHEN ts_started IS NOT NULL AND (ts_ended IS NULL OR ts_ended >= CURRENT_DATE() - INTERVAL 6 MONTH) THEN TRUE
            ELSE FALSE 
    END AS has_experiment_ran_last_6_months,
    CASE 
        WHEN ts_started IS NOT NULL AND (ts_ended IS NULL OR ts_ended >= CURRENT_DATE() - INTERVAL 1 YEAR) THEN TRUE
            ELSE FALSE 
    END AS has_experiment_ran_last_year,
    ts_started AS ts_experiment_started,
    ts_ended AS ts_experiment_ended,
    NOW() AS ts_load
FROM
    datalake_sorting_hat_clean.experiment