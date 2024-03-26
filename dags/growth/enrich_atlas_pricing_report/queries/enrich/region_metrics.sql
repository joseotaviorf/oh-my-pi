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
        p.business_context,
        100*(ABS(sc.sale - p.p_50)/sc.sale) AS percentual_error
    FROM sale_contracts sc 
    JOIN datalake_ebdb_clean.house_predicted_price_aud p 
        ON sc.sk_house = p.id_house 
    JOIN dw_sale.fact_listings fl
        ON fl.sk_house = sc.sk_house
    WHERE
        p.business_context = 'SALE'
    QUALIFY 
        ROW_NUMBER() OVER(PARTITION BY p.id_house ORDER BY p.rev DESC) = 1        
),

sale_mdape AS (
    SELECT 
        dhl.house_city,
        p.business_context,
        APPROX_PERCENTILE(percentual_error, 0.5) AS mdape
    FROM sale_prices_errors p
    JOIN dw_public.dim_house_listing dhl
        ON p.sk_house = dhl.id_house
    WHERE 
        dhl.country_code != 'MX'
    GROUP BY 1, 2
),

rent_mdape AS (
    SELECT 
        dhl.house_city,
        business_context,
        APPROX_PERCENTILE(ABS(100.0*dc.rent / p_50 - 100), 0.5) AS mdape
    FROM dw_rent.fact_listing_rent_flows rf
    JOIN dw_public.dim_contract dc
        ON rf.sk_contract = dc.sk_contract
    JOIN dw_public.dim_house_listing dhl
        ON dhl.sk_house_listing = rf.sk_house_listing
    JOIN datalake_ebdb_clean.house_predicted_price hpp 
        ON rf.sk_house_listing/1000 = hpp.id_house 
    WHERE
        DATEDIFF(dt_start, CURRENT_DATE) <= 60
        AND business_context = 'RENT'
        AND dhl.country_code != 'MX'
    GROUP BY 1, 2  
),

union_context AS (
    SELECT 
        house_city,
        business_context,
        mdape
    FROM sale_mdape
    
    UNION 

    SELECT 
        house_city,
        business_context,
        mdape
    FROM rent_mdape
)
    
SELECT 
    COALESCE(fhl.sk_region, fl.sk_region) AS id_region,
    uc.house_city,
    business_context,
    mdape AS mdape_city
FROM union_context uc
LEFT JOIN dw_public.dim_house_listing dhl
    ON dhl.house_city = uc.house_city
    AND dhl.version > 0
LEFT JOIN dw_public.fact_house_listings fhl
    ON fhl.sk_house_listing = dhl.sk_house_listing
LEFT JOIN dw_sale.fact_listings fl
    ON fl.sk_house = dhl.id_house