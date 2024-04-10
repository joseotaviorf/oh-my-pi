WITH sale_contracts AS(
    SELECT
        fo.sk_house,
        fo.last_price_offered_by_buyer AS sale,
        date AS signed_date
    FROM dw_sale.fact_offers fo
    JOIN dw_public.dim_date dd
        ON dd.sk_date = fo.sk_sale_agreement_signed_date
    WHERE
        sk_sale_agreement_signed_date > 0
        AND DATEDIFF(dd.date, CURRENT_DATE) <= 60
        AND fo.last_price_offered_by_buyer BETWEEN 100000 AND 20000000
        AND fo.sk_house IS NOT NULL
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY sk_house ORDER BY signed_date DESC) = 1
),

sale_prices_errors AS (
    SELECT DISTINCT
        sc.sk_house,
        fl.sk_region,
        dr.city_name,
        p.business_context,
        100*(ABS(sc.sale - p.p_50)/sc.sale) AS percentual_error
    FROM sale_contracts sc
    JOIN datalake_ebdb_clean.house_predicted_price_aud p
        ON sc.sk_house = p.id_house
    JOIN dw_sale.fact_listings fl
        ON fl.sk_house = sc.sk_house
    JOIN dw_public.dim_region dr
        ON dr.sk_region = fl.sk_region
    WHERE
        p.business_context = 'SALE'
        AND dr.country_code != 'MX'
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY p.id_house ORDER BY p.rev DESC) = 1
),

sale_mdape AS (
    SELECT
        p.city_name,
        p.business_context,
        MEDIAN(percentual_error) AS mdape
    FROM sale_prices_errors p
    GROUP BY 1, 2
),

rent_mdape AS (
    SELECT
        dr.city_name,
        business_context,
        MEDIAN(ABS(100.0*dc.rent / p_50 - 100)) AS mdape
    FROM dw_rent.fact_listing_rent_flows rf
    JOIN dw_public.dim_contract dc
        ON rf.sk_contract = dc.sk_contract
    JOIN dw_public.dim_house_listing dhl
        ON dhl.sk_house_listing = rf.sk_house_listing
    JOIN datalake_ebdb_clean.house_predicted_price hpp
        ON dhl.id_house = hpp.id_house
    JOIN dw_public.dim_region dr
        ON dr.sk_region = rf.sk_region
    WHERE
        DATEDIFF(dt_start, CURRENT_DATE) <= 60
        AND business_context = 'RENT'
        AND dhl.country_code != 'MX'
    GROUP BY 1, 2
),

union_context AS (
    SELECT
        city_name,
        business_context,
        mdape
    FROM sale_mdape

    UNION

    SELECT
        city_name,
        business_context,
        mdape
    FROM rent_mdape
)

SELECT
    dr.sk_region AS id_region,
    uc.city_name,
    business_context,
    mdape AS mdape_city
FROM union_context uc
LEFT JOIN dw_public.dim_region dr
    ON dr.city_name = uc.city_name
