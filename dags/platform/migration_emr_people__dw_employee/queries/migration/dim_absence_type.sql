SELECT
    b.id_absence_type AS sk_absence_type,
    tl.name AS absence_type,
    IF(tl.name = 'Licença Sem Vencimentos', FALSE, TRUE) AS is_paid_leave,
    tl.name IN (
        'Afastamento Temporário por Acidente de Trabalho',
        'Afastamento Temporário por Doença',
        'Licença Parental - Responsável 1',
        'Licença Parental - Responsável 2'
    ) AS is_performa_protected,
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