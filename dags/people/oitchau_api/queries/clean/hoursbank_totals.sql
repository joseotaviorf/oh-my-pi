WITH deduped AS (
    SELECT
        uuid AS id_employee_profile,
        CAST(`date` AS DATE) AS dt_balanced,
        ts_load,
        totals AS hours_bank_totals,
        year,
        month,
        day,
        ROW_NUMBER() OVER (
            PARTITION BY uuid, CAST(`date` AS DATE)
            ORDER BY
                ts_load DESC NULLS LAST,
                year DESC,
                month DESC,
                day DESC
        ) AS row_number_latest
    FROM
        datalake_oitchau_raw.hoursbank_totals
    WHERE
        CAST(`date` AS DATE) BETWEEN DATE_ADD(DATE('{load_end_date}'), -44)
        AND DATE('{load_end_date}')
)
SELECT
    id_employee_profile,
    dt_balanced,
    ts_load,
    hours_bank_totals,
    year,
    month,
    day
FROM
    deduped
WHERE
    row_number_latest = 1
