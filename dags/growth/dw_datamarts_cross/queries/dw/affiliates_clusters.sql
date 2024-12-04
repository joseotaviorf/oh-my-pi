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
            WHEN sk_user IN (360754,912255,1711931,2257503) THEN 'Spinver'
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
        WHEN c.sk_user IN (5606133,4969562,5048723,5606058) THEN 'AAVs BH' /*IDs de BH com comportamento de Crawlers*/
        WHEN c.sk_user IN (899512,3872007,1058213,2616431,1254253) THEN 'Outros AAVs' /*5 ids com comportamento de conversão e indicação bem próximos de BH (todos nos mesmos sobrenomes)*/
        WHEN c.sk_user IN (10323641,11855730,9756347,705005,671522,5547871,934209,10705525,5606133,4969562,5048723,5606058,6868983,9610707,8827630,7622477,6755432,1684727,851641,7654138,4469939,9778059,6405750,1428213,9912487,2067910,678268,4319219,4238917,8744092,1806012,2383774,1374091,7885668,9209652,9155226,6919623,2398104,696365,1671762,7848282,407179,6483960,738249,9954047,667232,6768231,7918071,3736370,7649108,1395709,2692453,4320047,4317379,1092411,793525,705598,1724146,5734685,1238425,2534029,2616431,7477195,4526270,8907825,1684033,3351964,4608851,6702377,3738393,2845335,8598041,5127832,5792245,8606796,5127721,1545988,1350339,1052983,7657737,60146,4346716,9141837,4726286,2862195,2598119,4447009,899512,7905906,6707499,4346496,1058213,1254253,3872007,5846217,2573390,430354,5690397,1724436,5297354,8892379,1123493,882001,1014553,8663978,1857607,4488773,11077878,10954460,8775260,1864391)
        THEN 'Outros AAVs' /*Outros IDs com +250 prospects e menos que 4% de P2O*/
        WHEN c.sk_user IN (360754,912255,1711931,2257503) THEN 'Spinver'
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
WHERE c.month_start >= '2019-01-01'