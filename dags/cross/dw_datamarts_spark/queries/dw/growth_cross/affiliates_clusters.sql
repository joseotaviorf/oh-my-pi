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
        WHEN c.sk_user IN (60146,155727,224774,327605,356518,407179,430354,474473,574235,651382,666383,667232,671522,696365,705598,787090,793525,797173,871074,899512,934209,962530,1052983,1058213,1089178,1092411,1129881,1212601,1238425,1254253,1350339,1374091,1395709,1428213,1517555,1684727,1724146,1724436,1806012,1860463,2201049,2342204,2388924,2398104,2534029,2561560,2573390,2616431,2692453,2762685,2845335,3050751,3068335,3738393,3809331,3872007,4238917,4320047,4346496,4346716,4526270,4969562,5048723,5127721,5127832,5547871,5584563,5606058,5606133,5690397,5734685,5755447,5792245,5846217,6337236,6405750,6483960,6702377,6707499,6712241,6755432,6868983,6919623,7030032,7076869,7445289,7500320,7622477,7649108,7654138,7657737,7714520,7792506,7848282,7905906,7918071,7943313,7993766,626115,1014553,1671762,1985336,2037010,2143616,2447847,2799943,3715627,3931819,4178688,6767233,6893183,128181,273245,1232335,1634660,1740138,2386286,2810711,3772970,3795681,4037107,4298042,5811296,7155422,536053,2220429,2465366,4317379,5362236,5623037,5904909,6357593,6754769,6834932,346589,604027,686725,696168,698555,705005,882001,1295669,1864391,1981354,2045970,2067910,2177135,2335161,5297354,5945753,6768231,269498,303937,678267,966367,1176373,1182098,1846780,2446734,3647145,3905766,4608851,4992568,6312465,8598041,8606796)
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
