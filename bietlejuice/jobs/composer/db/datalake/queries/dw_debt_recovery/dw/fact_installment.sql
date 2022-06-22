SELECT
    i.`id` AS id_installment,
    i.id_negotiation,
    i.total_amount,
    i.status,
    i.purpose,
    i.payment_type,
    CASE
        WHEN i.ts_paid_difference <= 2 AND d.weekday_name = 'Saturday' THEN NULL
        WHEN i.ts_paid_difference = 1 AND d.weekday_name = 'Sunday' THEN NULL
        WHEN i.ts_paid_difference <= 3 AND d.weekday_name = 'Friday' AND d.is_brz_holiday = 'Holiday' THEN NULL
        WHEN i.ts_paid_difference = 1 AND d.weekend = 'Weekday' AND d.is_brz_holiday = 'Holiday' THEN NULL
        WHEN i.ts_paid_difference < 0 THEN NULL
        ELSE i.ts_paid_difference
    END AS days_paid_late,
    i.dt_due,
    i.ts_paid,
    CURRENT_TIMESTAMP AS ts_load,
    EXTRACT(YEAR FROM current_date) AS year,
    EXTRACT(MONTH FROM current_date) AS month,
    EXTRACT(DAY FROM current_date) AS day
FROM
    datalake_debt_recovery.installment AS i
LEFT JOIN
    dw_public.dim_date AS d
        ON d.date = i.ts_paid