WITH
get_max_snapshot AS (
    SELECT
        MAX(DATE(ts_load)) AS ts_max_snapshot,
        MAX(date_add(DATE_TRUNC('MONTH', ts_load),-1)) AS end_month
    FROM
        dw_velo.quintocred_ifrs_occurrence
),
base_garantia AS (
    SELECT
        *,
        max.end_month
    FROM
        dw_velo.quintocred_ifrs_occurrence o
    JOIN
        get_max_snapshot max
        ON DATE(o.ts_load) = max.ts_max_snapshot
),
base_garantia_added AS (
    SELECT
        *,
        DATEDIFF(DAY,dt_register,end_month) AS atraso,
        CASE
            WHEN date_trunc('MONTH', dt_register) = date_trunc('MONTH',ts_load - interval '1' MONTH) THEN 1
            ELSE 0
        END AS fluxo_estoque,
        CASE
            WHEN dt_paid > LAST_DAY(date_trunc('MONTH',ts_load - interval '1' MONTH)) OR dt_paid IS NULL THEN 0
            ELSE paid_amount
        END AS paid_amount_2
    FROM
        base_garantia
    WHERE
        dt_register <= end_month
),
pivot_contaminacao_garantia AS (
    SELECT
        sk_propose,
        MAX(REPLACE(REPLACE(REPLACE(client_cpf_cnpj,'.',''),'-',''),'/','')) AS client_cpf_cnpj,
        ts_load,
        MAX(atraso) AS max_atraso
    FROM
        base_garantia_added
    WHERE
        open_amount > 0
    GROUP BY 1,3
),
base_garantia_added_final AS (
    SELECT
        baa.*,
        pc.max_atraso,
        CASE
            WHEN pc.max_atraso IS NULL AND atraso <=0  THEN 'a.Current'
            WHEN pc.max_atraso IS NULL AND atraso <=30  THEN 'b.1 a 30'
            WHEN pc.max_atraso IS NULL AND atraso <=60  THEN 'c.31 a 60'
            WHEN pc.max_atraso IS NULL AND atraso <=90  THEN 'd.61 a 90'
            WHEN pc.max_atraso IS NULL AND atraso <=120  THEN 'e.91 a 120'
            WHEN pc.max_atraso IS NULL AND atraso <=150  THEN 'f.121 a 150'
            WHEN pc.max_atraso IS NULL AND atraso <=180  THEN 'g.151 a 180'
            WHEN pc.max_atraso IS NULL AND atraso >180  THEN 'h.>180'
            WHEN pc.max_atraso <= 0        THEN 'a.Current'
            WHEN pc.max_atraso <=30        THEN 'b.1 a 30'
            WHEN pc.max_atraso <=60        THEN 'c.31 a 60'
            WHEN pc.max_atraso <=90        THEN 'd.61 a 90'
            WHEN pc.max_atraso <=120       THEN 'e.91 a 120'
            WHEN pc.max_atraso <=150       THEN 'f.121 a 150'
            WHEN pc.max_atraso <=180       THEN 'g.151 a 180'
            ELSE 'h.>180'
        END AS delay_range
    FROM
        base_garantia_added AS baa
    LEFT JOIN
        pivot_contaminacao_garantia AS pc
        ON baa.sk_propose = pc.sk_propose
        AND baa.ts_load = pc.ts_load
)

SELECT
    b.sk_propose,
    b.client_cpf_cnpj,
    b.delay_range,
    b.max_atraso AS days_delay,
    ROUND(SUM(b.due_amount),2) AS due_amount,
    ROUND(SUM(b.paid_amount),2) AS paid_amount,
    ROUND(SUM(b.paid_amount_2),2) AS paid_amount_2,
    ROUND(SUM(b.open_amount),2) AS open_amount,
    ROUND(SUM(IF(b.provisional_group = 'Rescisão' ,b.open_amount, 0)), 2) AS open_amount_termination,
    ROUND(SUM(IF(b.provisional_group = 'Garantia' ,b.open_amount, 0)), 2) AS open_amount_guarantee,
    ROUND(SUM(b.discount_value),2) AS discount_value,
    IF(p.dt_analyst_annulment_input IS NULL, True, False) AS is_contract_active,
    p.dt_contract_started,
    p.dt_analyst_annulment_input,
    NOW() AS ts_load
FROM
    base_garantia_added_final b
LEFT JOIN
    dw_velo.fact_velo_propose p
    ON b.sk_propose = p.sk_propose
GROUP BY 1, 2, 3, 4, 12, 13, 14
