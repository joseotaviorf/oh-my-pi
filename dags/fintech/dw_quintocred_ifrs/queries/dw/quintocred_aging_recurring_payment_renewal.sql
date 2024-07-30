WITH
get_max_snapshot AS (
    SELECT
        MAX(DATE(ts_load)) AS ts_max_snapshot,
        MAX(DATE_ADD(DATE_TRUNC('MONTH', ts_load),-1)) AS end_month
    FROM
        dw_velo.quintocred_ifrs_recurring_payment
),
renewal AS (
    SELECT
        *,
        ROW_NUMBER() OVER(PARTITION BY propose ORDER BY dt_due DESC) AS rn
    FROM
        datalake_rental_guarantee_platform_clean.renewal
),
snap AS (
    SELECT
        b.*,
        DATE_DIFF(COALESCE(b.dt_paid,end_month),b.dt_due) AS dias_atraso_aj,
        DATE_DIFF(end_month,b.dt_due) AS dias_atraso_vencido,
        CASE
            WHEN LEN(REPLACE(REPLACE(REPLACE(b.client_cpf_cnpj,'.',''),'-',''),'/','')) < 11 THEN LPAD(REPLACE(REPLACE(REPLACE(b.client_cpf_cnpj,'.',''),'-',''),'/',''),11,'0')
            WHEN LEN(REPLACE(REPLACE(REPLACE(b.client_cpf_cnpj,'.',''),'-',''),'/','')) IN (12,13) THEN LPAD(REPLACE(REPLACE(REPLACE(b.client_cpf_cnpj,'.',''),'-',''),'/',''),14,'0')
            ELSE REPLACE(REPLACE(REPLACE(b.client_cpf_cnpj,'.',''),'-',''),'/','')
        END AS client_cpf_cnpj_ajustado,
        DATE(r.dt_due) AS dt_renovacao
    FROM
        dw_velo.quintocred_ifrs_recurring_payment b
    JOIN
        get_max_snapshot max
        ON DATE(b.ts_load) = max.ts_max_snapshot
    LEFT JOIN
        renewal r
        ON b.sk_propose = CAST(r.propose AS VARCHAR(10))
        AND r.rn=1
    WHERE
        b.dt_register <= max.end_month
        AND (b.is_delinquency_renovacao = true)
        AND b.open_amount > 0
        AND b.provisional_group <> 'Taxa de ativação'
),
max_dias_atraso AS (
    SELECT
        b.client_cpf_cnpj_ajustado,
        b.sk_propose,
        MONTHS_BETWEEN(DATE_TRUNC('MONTH', b.ts_load),DATE_TRUNC('MONTH', r.dt_due)) AS months_overdue,
        12 - MONTHS_BETWEEN(DATE_TRUNC('MONTH', b.ts_load),DATE_TRUNC('MONTH', r.dt_due)) AS months_due,
        MAX(b.dias_atraso_aj) AS max_delay_due,
        MAX(b.dias_atraso_vencido) AS max_delay_overdue
    FROM
        snap b
    JOIN
        get_max_snapshot max
        ON DATE(b.ts_load) = max.ts_max_snapshot
    LEFT JOIN renewal r
        ON b.sk_propose = CAST(r.propose AS VARCHAR(10))
        AND r.rn=1
    WHERE
        b.dt_register <= max.end_month
        AND (b.is_delinquency_renovacao = true)
    GROUP BY 1,2,3,4
),
base_final AS (
    SELECT
        b.sk_propose,
        b.client_cpf_cnpj_ajustado AS client_cpf_cnpj,
        CASE
            WHEN (max.max_delay_overdue IS NULL OR max.max_delay_overdue =0)    THEN 'a.Current'
            WHEN max.max_delay_overdue <= 0        THEN 'a.Current'
            WHEN max.max_delay_overdue <=30        THEN 'b.1 a 30'
            WHEN max.max_delay_overdue <=60        THEN 'c.31 a 60'
            WHEN max.max_delay_overdue <=90        THEN 'd.61 a 90'
            WHEN max.max_delay_overdue <=120       THEN 'e.91 a 120'
            WHEN max.max_delay_overdue <=150       THEN 'f.121 a 150'
            WHEN max.max_delay_overdue <=180       THEN 'g.151 a 180'
            ELSE 'h.>180'
        END AS delay_range_overdue,
        max.max_delay_overdue AS max_delay_overdue,
        max.months_overdue,
        ROUND((b.open_amount / 12) * months_overdue,2) AS value_overdue,
        SUM(b.due_amount) AS due_amount,
        SUM(b.paid_amount) AS paid_amount,
        SUM(b.discount_value) AS discount_value,
        SUM(b.open_amount) AS open_amount,
        b.dt_due,
        dt_renovacao AS dt_renewal
    FROM
        snap b
    JOIN
        get_max_snapshot ms
        ON DATE(b.ts_load) = ms.ts_max_snapshot
    LEFT JOIN
        max_dias_atraso max
        ON b.client_cpf_cnpj_ajustado = max.client_cpf_cnpj_ajustado
        AND b.sk_propose = max.sk_propose
    GROUP BY 1,2,3,4,5,6,11,12
)

SELECT
    *,
    CASE
        WHEN delay_range_overdue = 'a.Current' THEN 0.35
        WHEN delay_range_overdue = 'b.1 a 30' THEN 0.86
        ELSE 1
    END AS pdd_percentage,
    CASE
        WHEN delay_range_overdue = 'a.Current' THEN ROUND((value_overdue * 0.35),2)
        WHEN delay_range_overdue = 'b.1 a 30' THEN ROUND((value_overdue * 0.86),2)
        ELSE ROUND((value_overdue * 1),2)
    END AS pdd,
    NOW() AS ts_load
FROM
    base_final
