WITH combinations AS (
    SELECT
        dset_1.sk_event_type AS sk_first_event_type,
        dset_2.sk_event_type AS sk_second_event_type,
        dset_1.abbreviation || '2' || dset_2.abbreviation AS conversion_abbreviation,
        dset_1.event_name || '_TO_' || dset_2.event_name AS conversion_name,
        dset_1.abbreviation AS first_event_abbreviation,
        dset_2.abbreviation AS second_event_abbreviation,
        dset_1.event_name AS first_event_name,
        dset_2.event_name AS second_event_name,
        EXPLODE(SEQUENCE(0, 20)) AS weeks -- Make all combinations of weeks 0 to 20+.
    FROM
        dw_sale.dim_sale_event_type AS dset_1
    JOIN
        dw_sale.dim_sale_event_type AS dset_2
            ON dset_1.sk_event_type != dset_2.sk_event_type
    WHERE
        dset_1.sk_event_type != -1
        AND dset_2.sk_event_type != -1
),
days_combination AS (
    SELECT
        sk_first_event_type,
        sk_second_event_type,
        conversion_abbreviation,
        conversion_name,
        first_event_abbreviation,
        second_event_abbreviation,
        first_event_name,
        second_event_name,
        weeks,
        EXPLODE(SEQUENCE(-6,6)) AS calendar_days_in_week,
        calendar_days_in_week + weeks * 7 AS calendar_days -- W1 can go from 1 to 13 days, for example. 1 * 7 - 6 to 1 * 7 + 6.
    FROM
        combinations
)
SELECT
    sk_first_event_type || '-' || sk_second_event_type || '-' || weeks || '-' || calendar_days AS sk_cohort_type,
    CASE
        WHEN weeks >= 20 THEN 'W20+'
        ELSE 'W' || weeks
    END AS week_number_up_to_20,
    CASE
        WHEN weeks >= 5 THEN 'W5+'
        ELSE 'W' || weeks
    END AS week_number_up_to_5,
    CASE
        WHEN calendar_days >= 140 THEN '140+'
        ELSE calendar_days
    END AS calendar_days,
    CASE
        WHEN calendar_days BETWEEN 0 AND 6 THEN '0-6'
        WHEN calendar_days BETWEEN 7 AND 14 THEN '7-14'
        WHEN calendar_days BETWEEN 15 AND 30 THEN '15-30'
        WHEN calendar_days BETWEEN 31 AND 60 THEN '31-60'
        WHEN calendar_days BETWEEN 61 AND 90 THEN '61-90'
        WHEN calendar_days BETWEEN 91 AND 120 THEN '91-120'
        ELSE '121+'
    END AS calendar_days_exponential,
    CASE
        WHEN calendar_days >= 140 THEN '140+'
        ELSE 7 * FLOOR(calendar_days / 7) || '-' || (7 * FLOOR(calendar_days / 7) + 6)
    END AS calendar_days_by_week,
    CASE
        WHEN calendar_days >= 120 THEN '120+'
        ELSE 30 * FLOOR(calendar_days / 30) || '-' || (30 * FLOOR(calendar_days / 30) + 29)
    END AS calendar_days_by_month,
    conversion_abbreviation,
    conversion_name,
    first_event_abbreviation,
    second_event_abbreviation,
    first_event_name,
    second_event_name,
    NOW() AS ts_load
FROM
    days_combination
WHERE
    calendar_days BETWEEN 0 AND 140