SELECT
    uuid AS id_employee_profile,
    CAST(`date` AS DATE) AS dt_balanced,
    ts_load,
    totals AS hours_bank_totals,
    year,
    month,
    day
FROM
    datalake_oitchau_raw.hoursbank_totals
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}')
        AND DATE('{load_end_date}')
