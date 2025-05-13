WITH date_month_range as (
    SELECT
        DISTINCT
        sk_date,
        year_month,
        month_start,
        month_end
    FROM dw_public.dim_date AS d
    WHERE  d.month_start = d.date
    AND DATE_TRUNC('month', month_start) <= DATE_TRUNC('month', current_date)
),
metrics AS(
    SELECT
        dt.month_start,
        DATE(dua.ts_joined_program) AS joined_program_date,
        dua.sk_user,
        dua.type,
        COUNT(CASE WHEN llf.sk_lead_date > 0 AND dtl.date BETWEEN dt.month_start AND dt.month_end AND llf.context_lead = 'Rent' THEN 1 ELSE NULL END) AS rent_lead,
        COUNT(CASE WHEN llf.sk_lead_date > 0 AND dtl.date BETWEEN dt.month_start AND dt.month_end AND llf.context_lead = 'Sale' THEN 1 ELSE NULL END) AS sale_lead,
        COUNT(CASE WHEN llf.sk_lead_date > 0 AND dtl.date BETWEEN dt.month_start AND dt.month_end AND llf.context_lead = 'Hybrid' THEN 1 ELSE NULL END)/2 AS hybrid_lead,
        COUNT(CASE WHEN llf.sk_lead_date > 0 AND dtl.date BETWEEN dt.month_start AND dt.month_end THEN 1 ELSE NULL END) AS total_lead,
        COUNT(CASE WHEN llf.sk_prospect_date > 0 AND DATE_TRUNC('month', dtp.date) = DATE_TRUNC('month', dtl.date) AND dtl.date BETWEEN dt.month_start AND dt.month_end AND llf.context_prospect = 'Rent' THEN 1 ELSE NULL END) AS rent_prospect,
        COUNT(CASE WHEN llf.sk_prospect_date > 0 AND DATE_TRUNC('month', dtp.date) = DATE_TRUNC('month', dtl.date) AND dtl.date BETWEEN dt.month_start AND dt.month_end AND llf.context_prospect = 'Sale' THEN 1 ELSE NULL END) AS sale_prospect,
        COUNT(CASE WHEN llf.sk_prospect_date > 0 AND DATE_TRUNC('month', dtp.date) = DATE_TRUNC('month', dtl.date) AND dtl.date BETWEEN dt.month_start AND dt.month_end AND llf.context_prospect = 'Hybrid' THEN 1 ELSE NULL END)/2 AS hybrid_prospect,
        COUNT(CASE WHEN llf.sk_prospect_date > 0 AND DATE_TRUNC('month', dtp.date) = DATE_TRUNC('month', dtl.date) AND dtl.date BETWEEN dt.month_start AND dt.month_end THEN 1 ELSE NULL END) AS total_prospect
    FROM
        dw_public.dim_user_affiliate AS dua
    LEFT JOIN date_month_range AS dt
        ON dt.month_start BETWEEN DATE_TRUNC('month', dua.ts_joined_program) AND current_date
    LEFT JOIN dw_datamarts.lead_listing_flows AS llf
        ON dua.sk_user = llf.sk_user_lead_affiliate
    LEFT JOIN dw_public.dim_date AS dtl
        ON dtl.sk_date = llf.sk_lead_date
    LEFT JOIN dw_public.dim_date AS dtp
        ON dtp.sk_date = llf.sk_prospect_date
    GROUP BY 1,2,3,4

),
aux_sum AS (
    SELECT
        month_start,
        joined_program_date,
        m.sk_user,
        type,
        rent_lead,
        sale_lead,
        hybrid_lead,
        total_lead,
        rent_prospect,
        sale_prospect ,
        hybrid_prospect,
        total_prospect,
        SUM(total_lead) AS sum_total_lead,
        SUM(total_prospect) AS sum_total_prospect,
        SUM(total_lead) OVER (PARTITION BY m.sk_user ORDER BY month_start ROWS UNBOUNDED PRECEDING) AS acum_lead,
        SUM(total_prospect) OVER (PARTITION BY m.sk_user ORDER BY month_start ROWS UNBOUNDED PRECEDING) AS acum_prospect
    FROM
        metrics AS m
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12

),
calculated_metrics AS (
    SELECT
        month_start,
        joined_program_date,
        sk_user,
        type,
        rent_lead,
        sale_lead,
        hybrid_lead,
        total_lead,
        rent_prospect,
        sale_prospect ,
        hybrid_prospect,
        total_prospect,
        LAG(sum_total_lead,1) OVER (PARTITION BY sk_user ORDER BY month_start) AS lead_prev_month,
        LAG(sum_total_prospect,1) OVER (PARTITION BY sk_user ORDER BY month_start) AS prospect_prev_month,
        acum_lead,
        acum_prospect
    FROM
        aux_sum
),
clusters AS(
    SELECT
        month_start,
        DATE_FORMAT(month_start, 'yyyy/MM') AS year_month,
        sk_user,
        type,
        joined_program_date,
        rent_lead,
        sale_lead,
        hybrid_lead,
        total_lead,
        rent_prospect,
        sale_prospect,
        hybrid_prospect,
        total_prospect,
        lead_prev_month,
        prospect_prev_month,
        acum_lead,
        acum_prospect,
        CASE
            WHEN DATE_TRUNC('month', joined_program_date) = month_start THEN 'Novo usuário'
            WHEN DATE_TRUNC('month', joined_program_date) < month_start AND acum_lead = total_lead AND acum_prospect = total_prospect AND prospect_prev_month = 0 THEN 'Nunca Ativo em Lead'
            WHEN DATE_TRUNC('month', joined_program_date) < month_start AND acum_lead > total_lead AND acum_prospect = total_prospect AND prospect_prev_month = 0 THEN 'Nunca Ativo em Prospect'
            WHEN DATE_TRUNC('month', joined_program_date) < month_start AND acum_lead > total_lead AND acum_lead > 0 AND acum_prospect > 0 AND prospect_prev_month = 0 THEN 'Inativo'
            WHEN DATE_TRUNC('month', joined_program_date) < month_start AND prospect_prev_month > 0 THEN 'Ativo no periodo anterior'
            ELSE NULL
        END AS cluster
    FROM calculated_metrics
),
first_inactivation AS(
    SELECT
        sk_user,
        MIN(month_start) AS first_inactivation
    FROM clusters
    WHERE cluster = 'Inativo'
    GROUP BY 1
)
SELECT
    c.month_start,
    c.year_month,
    c.sk_user,
    c.type,
    c.joined_program_date,
    c.rent_lead,
    c.sale_lead,
    c.hybrid_lead,
    c.total_lead,
    c.rent_prospect,
    c.sale_prospect,
    c.hybrid_prospect,
    c.total_prospect,
    c.lead_prev_month,
    c.prospect_prev_month,
    c.acum_lead,
    c.acum_prospect,
    c.cluster,
    CASE
        WHEN c.sk_user < 0 THEN NULL
        WHEN avc.sk_user IS NOT NULL THEN avc.affiliate_volumetry
        WHEN c.cluster = 'Novo usuário' THEN 'Novos Afiliados'
        WHEN c.cluster IN ('Nunca Ativo em Prospect', 'Nunca Ativo em Lead') THEN 'Nunca Ativos'
        WHEN c.cluster = 'Ativo no periodo anterior' THEN 'Baixo volume - ativo'
        WHEN c.cluster = 'Inativo' THEN 'Baixo volume - inativo'
        ELSE 'Not Mapped'
    END AS affiliate_volumetry,
    f.first_inactivation
FROM clusters AS c
LEFT JOIN first_inactivation AS f
    ON f.sk_user = c.sk_user
LEFT JOIN
    datalake_gsheets_clean.affiliate_volumetry_cluster AS avc
    ON c.sk_user = avc.sk_user
WHERE c.month_start >= '2019-01-01'
