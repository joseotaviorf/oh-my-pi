/*
 Rateio de acordo com os prospects da última semana, vindos de afiliados que entraram no mês do prospect (new_users),
 com tracking_source facebook ou google e campanha não branded
 */
WITH
count_prospects AS (
    SELECT
        dd_p.week_start,
        dr.city_group,
        CASE 
            WHEN REGEXP_LIKE(dua.tracking_campaign, '(branded)|(institucional)') AND REGEXP_LIKE(dua.tracking_campaign, '(non-branded)')
                THEN true
            ELSE false 
        END AS campaign_is_branded,
        COUNT(CASE WHEN dd_p.year_month = dd_aff.year_month THEN 1 END) new_user_prospects
    FROM
        dw_public.fact_house_listing_flows f
    JOIN dw_public.dim_date dd_p
        ON dd_p.sk_date =f.sk_prospect_date
    JOIN dw_public.dim_user du
        ON f.sk_user_lead_affiliate = du.sk_user
    JOIN dw_public.dim_user_affiliate dua
        ON dua.sk_user_affiliate = du.dados_afiliado_id
    JOIN dw_public.dim_date dd_aff
        ON dd_aff.date = DATE(du.dadosafiliado_inicio_atuacao)
    JOIN dw_public.dim_region dr
        ON f.sk_region = dr.sk_region
    WHERE
        f.mkt_origin = 'Indica Aí - General'
        AND REGEXP_LIKE(dua.tracking_source, '(google)|(facebook)')
        AND f.sk_prospect_date>=20190101
        AND dr.city_group IS NOT NULL
    GROUP BY 
        1,2,3
    HAVING 
        campaign_is_branded = false
),
dim_distinct AS ( --incluir combinações semana/cidade sem resultado
    SELECT DISTINCT
         dd.sk_date,
         dd.week_start,
         dr.city_group
    FROM
         dw_public.dim_date dd, dw_public.dim_region dr
    WHERE
        dd.sk_date>=20190101
        AND dd.date < current_date
),
temp AS ( --Calculo do share por semana
    SELECT DISTINCT
        ddt.week_start,
        ddt.city_group,
        (
            CAST(sum(t.new_user_prospects) OVER (PARTITION BY ddt.week_start, ddt.city_group) AS FLOAT) /
            NULLIF(CAST(sum(t.new_user_prospects) OVER (PARTITION BY ddt.week_start) AS FLOAT), 0)
        ) AS current_share
    FROM
        dim_distinct ddt
    LEFT JOIN count_prospects t
        ON ddt.week_start = t.week_start
        AND ddt.city_group = t.city_group
),
share AS (--pegando o share da ultima semana
    SELECT
        *,
        lead(current_share,1) OVER (PARTITION BY city_group ORDER BY week_start DESC) AS share
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
    ON d.week_start=s.week_start
    AND d.city_group=s.city_group