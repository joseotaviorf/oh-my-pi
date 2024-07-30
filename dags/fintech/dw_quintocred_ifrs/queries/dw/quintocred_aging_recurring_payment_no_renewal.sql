WITH
get_max_snapshot AS (
    SELECT
        MAX(DATE(ts_load)) AS ts_max_snapshot,
        MAX(date_add(DATE_TRUNC('MONTH', ts_load),-1)) AS end_month
    FROM
        dw_velo.quintocred_ifrs_recurring_payment
),
snap AS (
    SELECT
        *,
        DATE_DIFF(COALESCE(dt_paid,end_month),dt_due) AS dias_atraso_aj,
        CASE
            WHEN LEN(REPLACE(REPLACE(REPLACE(b.client_cpf_cnpj,'.',''),'-',''),'/','')) < 11 THEN LPAD(REPLACE(REPLACE(REPLACE(b.client_cpf_cnpj,'.',''),'-',''),'/',''),11,'0')
            WHEN LEN(REPLACE(REPLACE(REPLACE(b.client_cpf_cnpj,'.',''),'-',''),'/','')) IN (12,13) THEN LPAD(REPLACE(REPLACE(REPLACE(b.client_cpf_cnpj,'.',''),'-',''),'/',''),14,'0')
            ELSE REPLACE(REPLACE(REPLACE(b.client_cpf_cnpj,'.',''),'-',''),'/','')
        END AS client_cpf_cnpj_ajustado
    FROM
        dw_velo.quintocred_ifrs_recurring_payment b
    JOIN
        get_max_snapshot max
        ON DATE(b.ts_load) = max.ts_max_snapshot
    WHERE
        b.dt_register <= max.end_month
        AND (b.is_delinquency_renovacao = false OR b.is_delinquency_renovacao IS NULL)
        AND b.open_amount > 0
        AND b.provisional_group <> 'Taxa de ativação'
),
max_dias_atraso AS (
    SELECT
        b.sk_propose,
        max(b.dias_atraso_aj) AS max_delay_due
    FROM
        snap b
    JOIN
        get_max_snapshot max
        ON DATE(b.ts_load) = max.ts_max_snapshot
    WHERE
        b.dt_register <= max.end_month
        AND (b.is_delinquency_renovacao = false OR b.is_delinquency_renovacao IS NULL)
    GROUP BY 1
),
base AS (
    SELECT
        b.sk_propose,
        b.client_cpf_cnpj_ajustado,
        b.dt_due,
        NULL AS months_overdue,
        NULL AS months_due,
        NULL AS value_overdue,
        NULL AS value_due,
        NULL AS delay_range_overdue,
        CASE
            WHEN (max.max_delay_due is null or max.max_delay_due =0)    THEN 'a.Current'
            WHEN max.max_delay_due <= 0        THEN 'a.Current'
            WHEN max.max_delay_due <=30        THEN 'b.1 a 30'
            WHEN max.max_delay_due <=60        THEN 'c.31 a 60'
            WHEN max.max_delay_due <=90        THEN 'd.61 a 90'
            WHEN max.max_delay_due <=120       THEN 'e.91 a 120'
            WHEN max.max_delay_due <=150       THEN 'f.121 a 150'
            WHEN max.max_delay_due <=180       THEN 'g.151 a 180'
            ELSE 'h.>180'
        END AS delay_range_due,
        NULL AS max_delay_overdue,
        max.max_delay_due AS max_delay_due,
        SUM(b.due_amount) AS due_amount,
        SUM(b.paid_amount) AS paid_amount,
        SUM(b.discount_value) AS discount_amount,
        SUM(b.open_amount) as open_amount
    FROM
        snap b
    JOIN
        get_max_snapshot ms
        ON DATE(b.ts_load) = ms.ts_max_snapshot
    LEFT JOIN
        max_dias_atraso max
        ON b.sk_propose = max.sk_propose
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11
)

SELECT
    sk_propose,
    client_cpf_cnpj_ajustado AS client_cpf_cnpj,
    delay_range_due,
    SUM(due_amount) AS due_amount,
    SUM(paid_amount) AS paid_amount,
    SUM(discount_amount) AS discount_amount,
    SUM(open_amount) AS open_amount,
    CASE
        WHEN delay_range_due = 'a.Current' THEN 0.35
        WHEN delay_range_due = 'b.1 a 30' THEN 0.86
        ELSE 1
    END AS pdd_percentage,
    CASE
        WHEN delay_range_due = 'a.Current' THEN ROUND((SUM(open_amount) * 0.35),2)
        WHEN delay_range_due = 'b.1 a 30' THEN ROUND((SUM(open_amount) * 0.86),2)
        ELSE ROUND((SUM(open_amount) * 1),2)
    END AS pdd,
    MIN(dt_due) AS dt_due,
    NOW() AS ts_load
FROM
    base
GROUP BY 1,2,3,8
