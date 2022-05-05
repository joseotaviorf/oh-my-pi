WITH last_charge_created AS (
    SELECT 
        id,
        MAX(ts_created) AS ts_last_created
    FROM 
        datalake_rental_guarantee_clean.charge
    GROUP BY 1
),
last_contract_guarantee_updated AS (
    SELECT
        id AS id_guarantee,
        MAX(ts_updated) AS ts_last_updated
    FROM
        datalake_rental_guarantee_clean.guarantee
    GROUP BY 1 
),
charge_info AS (
    SELECT
        c.id_guarantee,
        c.id,
        CASE
            WHEN c.charge_type = 'BILL' THEN 12
            ELSE c.installments
        END AS installments,
        c.charge_status,
        c.charge_type,
        c.ts_created
    FROM 
        datalake_rental_guarantee_clean.charge AS c
    INNER JOIN
        last_charge_created lcu
            ON c.id = lcu.id
            AND c.ts_created = lcu.ts_last_created
),
guarantee AS (
    SELECT 
        g.id_contract_ebdb,
        g.id AS id_guarantee,
        ci.id AS id_charge,
        g.ts_created AS ts_guarantee_created,
        ci.ts_created AS ts_charge_created,
        ADD_MONTHS(DATE_TRUNC('month', ci.ts_created), ci.installments) AS dt_charge_end,
        DATE_TRUNC('month',ci.ts_created) AS dt_charge_started,
        ci.installments,
        g.ts_paid AS ts_guarantee_paid,
        g.guarantee_status,
        g.base_value,
        g.final_value,
        ((g.final_value/100/installments)/1.0738)*0.825 AS monthly_revenue,
        ci.charge_status,
        ci.charge_type
    FROM
        datalake_rental_guarantee_clean.guarantee AS g
    INNER JOIN 
        charge_info AS ci
            ON g.id = ci.id_guarantee
    INNER JOIN
        last_contract_guarantee_updated AS lcgu
            ON lcgu.id_guarantee = g.id
            AND g.ts_updated = lcgu.ts_last_updated
    WHERE
        g.id_contract_ebdb IS NOT NULL
        AND g.ts_paid IS NOT NULL
        AND ci.charge_status = 'CAPTURED' 
)
SELECT
DISTINCT
    gb.id_guarantee,
    gb.id_contract_ebdb,
    gb.id_charge,
    gb.guarantee_status,
    gb.charge_status,
    gb.charge_type,
    gb.installments AS total_installments,
    (1+MONTHS_BETWEEN(ts_charge_created, dd.month_start)) AS installment_number,
    gb.monthly_revenue,
    dd.month_start AS accrual_year_month,
    gb.ts_guarantee_created,
    gb.ts_charge_created,
    gb.ts_guarantee_paid
FROM guarantee AS gb
INNER JOIN
    datalake_quintoandar.aux_date AS dd
        ON dd.date BETWEEN dt_charge_started AND dt_charge_end
WHERE
    (1+MONTHS_BETWEEN(ts_charge_created, dd.month_start)) <= installments
    AND dd.month_start <= current_date