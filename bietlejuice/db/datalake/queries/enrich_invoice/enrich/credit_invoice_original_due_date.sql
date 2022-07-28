WITH credit_holidays AS (
    SELECT
        12 AS day,
        10 AS month,
        "Nossa Sra. Aparecida - Padroeira do Brasil" AS holiday_name
    UNION ALL
    SELECT
        1 AS day,
        1 AS month,
        "Confraternização Universal" AS holiday_name
    UNION ALL
    SELECT
        15 AS day,
        11 AS month,
        "Proclamação da República" AS holiday_name
    UNION ALL
    SELECT
        7 AS day,
        9 AS month,
        "Independência do Brasil" AS holiday_name
    UNION ALL
    SELECT
        1 AS day,
        5 AS month,
        "Dia do Trabalho" AS holiday_name
    UNION ALL
    SELECT
        21 AS day,
        4 AS month,
        "Tiradentes" AS holiday_name
    UNION ALL
    SELECT
        31 AS day,
        12 AS month,
        "Ano Novo" AS holiday_name
    UNION ALL
    SELECT
      2 AS day,
      11 AS month,
      "Finados" AS holiday_name
    UNION ALL
    SELECT
        24 AS day,
        12 AS month,
        "Natal" AS holiday_name
    UNION ALL
    SELECT
        25 AS day,
        12 AS month,
        "Natal" AS holiday_name
), invoices AS (
    SELECT
        inv.id,
        inv.id_contract,
        inv.status,
        inv.paid_amount,
        inv.ts_paid,
        inv.ts_created,
        inv.status,
        inv.due_amount,
        inv.ts_due,
        inv.accrual_year_month,
        DATE_ADD(ADD_MONTHS(DATE_FORMAT(CAST(UNIX_TIMESTAMP(CONCAT(CAST(inv.accrual_year_month AS STRING),'01'),'yyyyMMdd') AS TIMESTAMP), 'yyyy-MM-dd'),1),6) AS static_original_due_date,
        inv.purpose,
        acc.type AS account_type
    FROM
        datalake_retsuko_clean.invoice AS inv
    JOIN
        datalake_retsuko_clean.account AS acc
    ON
        inv.id_contract = acc.id_contract
    WHERE
        acc.type = 'tenant'
        AND inv.due_amount < 0
), invoices_fixed AS (
  SELECT
        inv.id,
        inv.id_contract,
        inv.status,
        inv.paid_amount,
        inv.ts_paid,
        inv.ts_created,
        inv.status,
        inv.due_amount,
        inv.ts_due,
        inv.accrual_year_month,
        inv.static_original_due_date,
        (CASE
            WHEN
                hl.holiday_name = 'Natal'
                AND DAY(inv.static_original_due_date) = 24
                AND DAYOFWEEK(DATE_ADD(inv.static_original_due_date,2)) = 7 THEN DATE_ADD(inv.static_original_due_date, 4)
            WHEN
                hl.holiday_name = 'Natal'
                AND DAY(inv.static_original_due_date) = 24
                AND DAYOFWEEK(DATE_ADD(inv.static_original_due_date,2)) = 1 THEN DATE_ADD(inv.static_original_due_date, 3)
            WHEN
                hl.holiday_name = 'Natal'
                AND DAY(inv.static_original_due_date) = 25
                AND DAYOFWEEK(DATE_ADD(inv.static_original_due_date,1)) = 7 THEN DATE_ADD(inv.static_original_due_date, 3)
            WHEN
                hl.holiday_name = 'Natal'
                AND DAY(inv.static_original_due_date) = 25
                AND DAYOFWEEK(DATE_ADD(inv.static_original_due_date,1)) = 1 THEN DATE_ADD(inv.static_original_due_date, 2)
            WHEN
                hl.holiday_name = 'Natal'
                AND DAY(inv.static_original_due_date) = 24 THEN DATE_ADD(inv.static_original_due_date, 2)
            WHEN
                hl.holiday_name = 'Natal'
                AND DAY(inv.static_original_due_date) = 25 THEN DATE_ADD(inv.static_original_due_date, 1)
            WHEN
                hl.holiday_name IS NOT NULL
                AND DAYOFWEEK(inv.static_original_due_date) = 6 THEN DATE_ADD(inv.static_original_due_date,3)
            WHEN
                hl.holiday_name IS NOT NULL
                AND DAYOFWEEK(inv.static_original_due_date) = 2 THEN DATE_ADD(inv.static_original_due_date,1)
            WHEN
                hl.holiday_name IS NOT NULL
                AND DAYOFWEEK(inv.static_original_due_date) = 7 THEN DATE_ADD(inv.static_original_due_date,2)
            WHEN
                hl.holiday_name IS NOT NULL
                AND DAYOFWEEK(inv.static_original_due_date) = 1 THEN DATE_ADD(inv.static_original_due_date,1)
            WHEN
                hl.holiday_name IS NOT NULL THEN DATE_ADD(inv.static_original_due_date,1)
            WHEN
                hl.holiday_name IS NULL
                AND DAYOFWEEK(inv.static_original_due_date) = 7 THEN DATE_ADD(inv.static_original_due_date,2)
            WHEN
                hl.holiday_name IS NULL
                AND DAYOFWEEK(inv.static_original_due_date) = 1 THEN DATE_ADD(inv.static_original_due_date,1)
        ELSE
            inv.static_original_due_date END) AS original_due_date,
        inv.purpose,
        inv.account_type
  FROM
    invoices  AS inv
  LEFT JOIN
    credit_holidays AS hl
    ON
        hl.month = MONTH(inv.static_original_due_date)
        AND hl.day = DAY(inv.static_original_due_date)
)
SELECT
    inv.id,
    inv.id_contract AS id_contract_retsuko,
    ebdb_cntrct.id AS id_contract_ebdb,
    ebdb_cntrct.id_proposal,
    inv.purpose,
    inv.account_type,
    inv.status,
    inv.due_amount,
    inv.paid_amount,
    inv.ts_due,
    DATEDIFF(COALESCE(inv.ts_paid, CURRENT_DATE), inv.original_due_date) AS late_days,
    (CASE
        WHEN DATEDIFF(COALESCE(inv.ts_paid, CURRENT_DATE), inv.original_due_date) >= 10 THEN TRUE
    ELSE FALSE END) AS is_over_10,
    (CASE
        WHEN DATEDIFF(COALESCE(inv.ts_paid, CURRENT_DATE), inv.original_due_date) >= 15 THEN TRUE
    ELSE FALSE END) AS is_over_15,
    (CASE
        WHEN DATEDIFF(COALESCE(inv.ts_paid, CURRENT_DATE), inv.original_due_date) >= 20 THEN TRUE
    ELSE FALSE END) AS is_over_20,
    (CASE
        WHEN DATEDIFF(COALESCE(inv.ts_paid, CURRENT_DATE), inv.original_due_date) >= 30 THEN TRUE
    ELSE FALSE END) AS is_over_30,
    (CASE
        WHEN DATEDIFF(COALESCE(inv.ts_paid, CURRENT_DATE), inv.original_due_date) >= 40 THEN TRUE
    ELSE FALSE END) AS is_over_40,
    (CASE
        WHEN DATEDIFF(COALESCE(inv.ts_paid, CURRENT_DATE), inv.original_due_date) >= 50 THEN TRUE
    ELSE FALSE END) AS is_over_50,
    (CASE
        WHEN DATEDIFF(COALESCE(inv.ts_paid, CURRENT_DATE), inv.original_due_date) >= 60 THEN TRUE
    ELSE FALSE END) AS is_over_60,
    (CASE
        WHEN DATEDIFF(COALESCE(inv.ts_paid, CURRENT_DATE), inv.original_due_date) >= 70 THEN TRUE
    ELSE FALSE END) AS is_over_70,
    (CASE
        WHEN DATEDIFF(COALESCE(inv.ts_paid, CURRENT_DATE), inv.original_due_date) >= 80 THEN TRUE
    ELSE FALSE END) AS is_over_80,
    (CASE
        WHEN DATEDIFF(COALESCE(inv.ts_paid, CURRENT_DATE), inv.original_due_date) >= 90 THEN TRUE
    ELSE FALSE END) AS is_over_90,
    (CASE
        WHEN DATEDIFF(COALESCE(inv.ts_paid, CURRENT_DATE), inv.original_due_date) >= 100 THEN TRUE
    ELSE FALSE END) AS is_over_100,
    (CASE
        WHEN DATEDIFF(COALESCE(inv.ts_paid, CURRENT_DATE), inv.original_due_date) >= 110 THEN TRUE
    ELSE FALSE END) AS is_over_110,
    (CASE
        WHEN DATEDIFF(COALESCE(inv.ts_paid, CURRENT_DATE), inv.original_due_date) >= 120 THEN TRUE
    ELSE FALSE END) AS is_over_120,
    (CASE
        WHEN DATEDIFF(COALESCE(inv.ts_paid, CURRENT_DATE), inv.original_due_date) >= 140 THEN TRUE
    ELSE FALSE END) AS is_over_140,
    (CASE
        WHEN DATEDIFF(COALESCE(inv.ts_paid, CURRENT_DATE), inv.original_due_date) >= 160 THEN TRUE
    ELSE FALSE END) AS is_over_160,
    (CASE
        WHEN DATEDIFF(COALESCE(inv.ts_paid, CURRENT_DATE), inv.original_due_date) >= 180 THEN TRUE
    ELSE FALSE END) AS is_over_180,
    inv.accrual_year_month,
    inv.original_due_date,
    inv.ts_paid,
    rsk_cntrct.ts_signature,
    DATE(ebdb_cntrct.ts_updated) AS dt_contract_updated
FROM
    invoices_fixed AS inv
JOIN
    datalake_retsuko_clean.contract AS rsk_cntrct
ON
    inv.id_contract = rsk_cntrct.id
JOIN
    datalake_ebdb_clean.contract AS ebdb_cntrct
ON
    ebdb_cntrct.id = rsk_cntrct.id_external
WHERE
    inv.original_due_date IS NOT NULL
    AND rsk_cntrct.ts_signature IS NOT NULL
    AND DATEDIFF(inv.original_due_date, rsk_cntrct.ts_signature) > 0
    AND inv.status != 'canceled'
ORDER BY
    inv.original_due_date ASC
