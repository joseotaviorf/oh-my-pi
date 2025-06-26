SELECT
    MD5(type_or_status) AS sk_vacation_status,
    type_or_status AS vacation_status,
    NOW() AS ts_load
FROM
    datalake_pin_core_clean.assignment_extra_info
WHERE
    type_or_status IS NOT NULL
    AND information_type = 'Saldo de Férias'
GROUP BY
    type_or_status