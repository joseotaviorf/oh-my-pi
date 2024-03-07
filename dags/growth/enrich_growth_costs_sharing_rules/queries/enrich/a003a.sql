/*Share de custos com base na quantidade de prospects gerados no mes anterior com source = google
 Baseado na query em bi-etl-ejuice/bietlejuice/db/dw/queries/marketing/affiliates_costs/affiliates_national_campaigns_share.sql */

WITH affiliates AS ( --Afiliado por source= google
    SELECT DISTINCT
        dua.sk_user_affiliate,
        du.sk_user
    FROM
        dw_public.dim_user_affiliate dua
    JOIN
        dw_public.dim_user du
            ON du.dados_afiliado_id = dua.sk_user_affiliate
    WHERE
        tracking_source IN ('google')
),
t_row_count AS ( --contagem de prospects
    SELECT
        dd.sk_date,
        CAST(REPLACE(dd.year_month, '/', '') AS INTEGER) AS year_month,
        CAST(date_format(dd.last_month, 'yyyyMM') AS INTEGER) AS last_year_month,
        dr.city_group,
        COUNT(1) AS row_count
    FROM
        dw_public.fact_house_listing_flows fhlf
    JOIN affiliates af
        ON af.sk_user = fhlf.sk_user_lead_affiliate
    JOIN dw_public.dim_region dr
        ON dr.sk_region = fhlf.sk_region
    JOIN dw_public.dim_date dd
        ON dd.sk_date = fhlf.sk_prospect_date
    WHERE
        affiliate_type = 'Standard'
        AND city_group IS NOT NULL
    GROUP BY 1,2,3,4
),
dim_distinct AS (
    SELECT DISTINCT
        dd.sk_date,
        cast(replace(dd.year_month, '/', '') AS INTEGER) AS year_month,
        dr.city_group
    FROM
        dw_public.dim_date dd, dw_public.dim_region dr
    WHERE
        dd.date < current_date
),
temp AS ( --Calculo do share por mes
    SELECT DISTINCT
        ddt.year_month,
        ddt.city_group,
        (
            sum(row_count) OVER (PARTITION BY ddt.year_month, ddt.city_group) /
            NULLIF(sum(row_count) OVER (PARTITION BY ddt.year_month), 0)
           ) AS current_share
    FROM
        dim_distinct ddt
    LEFT JOIN t_row_count t
        ON ddt.year_month = t.year_month
        AND ddt.city_group = t.city_group
    WHERE ddt.sk_date>=20190101
),
share AS (
    SELECT
        *,
        lead(current_share,1) OVER (PARTITION BY city_group ORDER BY year_month DESC) AS share --pegando o share do ultimo mês
    FROM temp
)
SELECT
    d.sk_date AS id_date,
    '{id_rule}' AS id_rule,
    d.city_group,
    coalesce(s.share,0) AS share,
    'affiliates' AS funnel_side,
    CAST(NULL AS STRING) AS business_context
FROM
    dim_distinct d
JOIN share s
    ON d.year_month=s.year_month
    AND d.city_group=s.city_group