SELECT
    b.id_absence_type AS sk_absence_type,
    tl.name AS absence_type,
    b.maximum_duration AS max_days_allowed,
    NOW() AS ts_load
FROM
    datalake_pin_absence_clean.type AS b
INNER JOIN
    datalake_pin_absence_clean.type_translation AS tl
        ON b.id_absence_type = tl.id_absence_type
WHERE
    tl.language = 'US'
    AND b.dt_effective_started <= DATE('{load_end_date}') 
    AND b.dt_effective_ended >= DATE('{load_end_date}')  
    AND tl.dt_effective_started <= DATE('{load_end_date}') 
    AND tl.dt_effective_ended >= DATE('{load_end_date}') 