WITH date_month_range as (
    SELECT
        DISTINCT
        sk_date,
        year_month,
        month_start,
        month_end
    FROM dim_date d
    WHERE  d.month_start = d.date
    AND TEXT_TO_INT_ALT(year_month) <= TEXT_TO_INT_ALT(TO_CHAR(current_date, 'YYYYMM'))
),
metrics AS(
    SELECT
        dt.year_month,
        DATE(dua.ts_created) AS created_date,
        TO_CHAR(DATE(dua.ts_created), 'YYYY/MM') AS created_year_month,
        dua.sk_user,
        dua.type,
        COUNT(CASE WHEN llf.sk_lead_date > 0 AND dtl.date BETWEEN dt.month_start AND dt.month_end AND llf.context_lead = 'Rent' THEN 1 ELSE NULL END) AS rent_lead,
        COUNT(CASE WHEN llf.sk_lead_date > 0 AND dtl.date BETWEEN dt.month_start AND dt.month_end AND llf.context_lead = 'Sale' THEN 1 ELSE NULL END) AS sale_lead,
        COUNT(CASE WHEN llf.sk_lead_date > 0 AND dtl.date BETWEEN dt.month_start AND dt.month_end AND llf.context_lead = 'Hybrid' THEN 1 ELSE NULL END)/2 AS hybrid_lead,
        COUNT(CASE WHEN llf.sk_lead_date > 0 AND dtl.date BETWEEN dt.month_start AND dt.month_end THEN 1 ELSE NULL END) AS total_lead,
        COUNT(CASE WHEN llf.sk_prospect_date > 0 AND dtp.date BETWEEN dt.month_start AND dt.month_end AND llf.context_prospect = 'Rent' THEN 1 ELSE NULL END) AS rent_prospect,
        COUNT(CASE WHEN llf.sk_prospect_date > 0 AND dtp.date BETWEEN dt.month_start AND dt.month_end AND llf.context_prospect = 'Sale' THEN 1 ELSE NULL END) AS sale_prospect,
        COUNT(CASE WHEN llf.sk_prospect_date > 0 AND dtp.date BETWEEN dt.month_start AND dt.month_end AND llf.context_prospect = 'Hybrid' THEN 1 ELSE NULL END)/2 AS hybrid_prospect,
        COUNT(CASE WHEN llf.sk_prospect_date > 0 AND dtp.date BETWEEN dt.month_start AND dt.month_end THEN 1 ELSE NULL END) AS total_prospect
    FROM
        dim_user_affiliate dua
    LEFT JOIN date_month_range dt
        ON dt.year_month BETWEEN TEXT_TO_INT_ALT(TO_CHAR(DATE(dua.ts_created), 'YYYY/MM')) AND TEXT_TO_INT_ALT(TO_CHAR(current_date, 'YYYY/MM'))
    LEFT JOIN datamarts.lead_listing_flows llf
        ON dua.sk_user = llf.sk_user_lead_affiliate
    LEFT JOIN dim_date dtl
        ON dtl.sk_date = llf.sk_lead_date
    LEFT JOIN dim_date dtp
        ON dtp.sk_date = llf.sk_prospect_date
    GROUP BY 1,2,3,4,5
    order by 1 desc
),
calculated_metrics AS (
    SELECT
        *,
        LAG(SUM(total_lead),1) OVER (PARTITION BY sk_user ORDER BY TEXT_TO_INT_ALT(created_year_month)) AS lead_prev_month,
        LAG(SUM(total_prospect),1) OVER (PARTITION BY sk_user ORDER BY TEXT_TO_INT_ALT(created_year_month)) AS prospect_prev_month,
        SUM(total_lead) OVER (PARTITION BY sk_user ORDER BY TEXT_TO_INT_ALT(created_year_month) ROWS UNBOUNDED PRECEDING) acum_lead,
        SUM(total_prospect) OVER (PARTITION BY sk_user ORDER BY TEXT_TO_INT_ALT(created_year_month) ROWS UNBOUNDED PRECEDING) acum_prospect
    FROM
        metrics
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13
)
SELECT
    year_month,
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
        WHEN TEXT_TO_INT_ALT(created_year_month) = TEXT_TO_INT_ALT(year_month) THEN 'Novo usuário'
        WHEN TEXT_TO_INT_ALT(created_year_month) < TEXT_TO_INT_ALT(year_month) AND acum_lead = total_lead AND acum_prospect = total_prospect AND prospect_prev_month = 0 THEN 'Nunca Ativo em Lead'
        WHEN TEXT_TO_INT_ALT(created_year_month) < TEXT_TO_INT_ALT(year_month) AND acum_lead > total_lead AND acum_prospect = total_prospect AND prospect_prev_month = 0 THEN 'Nunca Ativo em Prospect'
        WHEN TEXT_TO_INT_ALT(created_year_month) < TEXT_TO_INT_ALT(year_month) AND acum_lead > total_lead AND acum_lead > 0 AND acum_prospect > 0 AND prospect_prev_month = 0 THEN 'Inativo'
        WHEN TEXT_TO_INT_ALT(created_year_month) < TEXT_TO_INT_ALT(year_month) AND prospect_prev_month > 0 THEN 'Ativo no periodo anterior'
        ELSE NULL
    END AS cluster
FROM calculated_metrics
WHERE TEXT_TO_INT_ALT(year_month) > 201812
ORDER BY 1 DESC