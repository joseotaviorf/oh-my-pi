WITH mexico_listing_flows AS (
    SELECT
        fhlf.sk_lead,
        fhlf.sk_lead_date,
        fhlf.sk_prospect_date,
        fhlf.sk_qualified_date,
        fhlf.sk_opportunity_date,
        fhlf.sk_first_listing_date,
        fhlf.sk_house_listing,
        fhlf.sk_region,
        fhlf.mkt_origin,
        fhlf.mkt_channel
    FROM
        dw_public.fact_house_listing_flows AS fhlf
    WHERE
        fhlf.sk_lead_date >= 20220601
        AND fhlf.country_code = 'MX'
),
mexico_channels AS (
SELECT
    fhlf.sk_lead,
    fhlf.sk_lead_date,
    fhlf.sk_prospect_date,
    fhlf.sk_qualified_date,
    fhlf.sk_opportunity_date,
    fhlf.sk_first_listing_date,
    fhlf.sk_house_listing,
    fhlf.sk_region,
    dl.country_code,
    'Mexico' AS country_name,
    COALESCE(dr.city_group, 'Not mapped') AS city_group,
    fhlf.mkt_origin AS supply_mkt_origin,
    CASE 
        WHEN fhlf.mkt_origin = 'Owner PWA' THEN fhlf.mkt_channel 
        WHEN fhlf.mkt_origin != 'Owner PWA' THEN fhlf.mkt_origin 
    END AS supply_mkt_origin_detailed,
    fhlf.mkt_channel,
    CASE 
        WHEN (dl.ub_page_name = 'Registrar Lead' OR dl.nome_anunciante = 'Monkey Lab') THEN 'Human Crawlers'
        WHEN dl.ub_page_name = 'Leads NAVENT' THEN 'Imuebles 24'
        WHEN dl.ub_page_name = 'Landing Owner Mexico' THEN 'Landing Page - PWA'
        ELSE fhlf.mkt_origin
    END AS mexico_channel,
    dl.ub_page_name,
    dl.nome_anunciante AS advertiser_name,
    dl.origem AS lead_origin,
    dl.criado_em AS ts_lead_created
FROM 
    mexico_listing_flows AS fhlf
LEFT JOIN 
    dw_public.dim_lead AS dl
        ON fhlf.sk_lead = dl.sk_lead
LEFT JOIN 
    dw_public.dim_region AS dr 
        ON fhlf.sk_region = dr.sk_region
)
SELECT
    sk_lead,
    sk_lead_date,
    sk_prospect_date,
    sk_qualified_date,
    sk_opportunity_date,
    sk_first_listing_date,
    sk_house_listing,
    sk_region,
    country_code,
    country_name,
    city_group,
    supply_mkt_origin,
    supply_mkt_origin_detailed,
    mkt_channel,
    CASE 
        WHEN mexico_channel = 'CIQ' THEN 'CIB'
        WHEN mexico_channel = 'Owner PWA' AND supply_mkt_origin_detailed = 'Organic'  THEN 'Organic Traffic'
        WHEN mexico_channel = 'Owner PWA' AND supply_mkt_origin_detailed = 'Paid' THEN 'Landing page - PWA'
        WHEN mexico_channel LIKE '%Indica Aí%' THEN 'Rifiere y Gana'
        ELSE mexico_channel
    END AS mexico_channel,
    ub_page_name,
    advertiser_name,
    lead_origin,
    ts_lead_created,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day
FROM
    mexico_channels