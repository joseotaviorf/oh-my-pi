WITH date_month_range as (
    SELECT
        DISTINCT
        sk_date,
        year_month,
        month_start,
        month_end
    FROM dim_date d
    WHERE  d.month_start = d.date
    AND DATE_TRUNC('month', month_start) <= DATE_TRUNC('month', current_date)
),
metrics AS(
    SELECT
        dt.month_start,
        DATE(dua.ts_created) AS created_date,
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
        dim_user_affiliate dua
    LEFT JOIN date_month_range dt
        ON dt.month_start BETWEEN DATE_TRUNC('month', dua.ts_created) AND current_date
    LEFT JOIN datamarts.lead_listing_flows llf
        ON dua.sk_user = llf.sk_user_lead_affiliate
    LEFT JOIN dim_date dtl
        ON dtl.sk_date = llf.sk_lead_date
    LEFT JOIN dim_date dtp
        ON dtp.sk_date = llf.sk_prospect_date
    GROUP BY 1,2,3,4

),
calculated_metrics AS (
    SELECT
        *,
        LAG(SUM(total_lead),1) OVER (PARTITION BY sk_user ORDER BY month_start) AS lead_prev_month,
        LAG(SUM(total_prospect),1) OVER (PARTITION BY sk_user ORDER BY month_start) AS prospect_prev_month,
        SUM(total_lead) OVER (PARTITION BY sk_user ORDER BY month_start ROWS UNBOUNDED PRECEDING) acum_lead,
        SUM(total_prospect) OVER (PARTITION BY sk_user ORDER BY month_start ROWS UNBOUNDED PRECEDING) acum_prospect
    FROM
        metrics
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
)
SELECT
    month_start,
    TO_CHAR(DATE(month_start), 'YYYY/MM') AS year_month,
    sk_user,
    type,
    created_date,
    total_lead,
    total_prospect,
    lead_prev_month,
    prospect_prev_month,
    acum_lead,
    acum_prospect,
    CASE
        WHEN sk_user IN (360754,912255,1711931,2257503) THEN 'Spinver'
        WHEN DATE_TRUNC('month', created_date) = DATE_TRUNC('month', month_start) THEN 'Novo usuário'
        WHEN DATE_TRUNC('month', created_date) < DATE_TRUNC('month', month_start) AND acum_lead = total_lead AND acum_prospect = total_prospect AND prospect_prev_month = 0 THEN 'Nunca Ativo em Lead'
        WHEN DATE_TRUNC('month', created_date) < DATE_TRUNC('month', month_start) AND acum_lead > total_lead AND acum_prospect = total_prospect AND prospect_prev_month = 0 THEN 'Nunca Ativo em Prospect'
        WHEN DATE_TRUNC('month', created_date) < DATE_TRUNC('month', month_start) AND acum_lead > total_lead AND acum_lead > 0 AND acum_prospect > 0 AND prospect_prev_month = 0 THEN 'Inativo'
        WHEN DATE_TRUNC('month', created_date) < DATE_TRUNC('month', month_start) AND prospect_prev_month > 0 THEN 'Ativo no periodo anterior'
        ELSE NULL
    END AS cluster
FROM calculated_metrics
WHERE month_start >= '2019/01/01'
ORDER BY 1 DESC