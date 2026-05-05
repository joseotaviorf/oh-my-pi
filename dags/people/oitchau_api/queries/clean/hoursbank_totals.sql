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
    MAKE_DATE(year, month, day) = DATE_ADD(DATE('{load_start_date}'), 1)
QUALIFY
    ROW_NUMBER() OVER (
        PARTITION BY uuid, CAST(`date` AS DATE)
        ORDER BY
            ts_load DESC NULLS LAST,
            year DESC,
            month DESC,
            day DESC
    ) = 1
