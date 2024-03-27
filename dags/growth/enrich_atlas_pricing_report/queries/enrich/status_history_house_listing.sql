/*
Imóveis FL com dt_price_updated e price nulos, são casos de imóveis com versão 000, 
até estao na fact_listing_price_changes, mas tem a versão 0 e não vem na query
*/

WITH listings AS (
    SELECT DISTINCT
        lbc.id_house,
        lbc.business_context,
        CASE
            WHEN lbc.business_context = 'RENT' THEN p_rent.ts_price_started
            WHEN lbc.business_context = 'SALE' THEN dd.date
        END AS dt_price_updated,
        CASE
            WHEN lbc.business_context = 'RENT' THEN p_rent.rent
            WHEN lbc.business_context = 'SALE' THEN p_sale.price
        END AS price,
        'FIRST_LISTING' AS status        
    FROM datalake_ebdb_clean.listing_business_context lbc
    LEFT JOIN dw_quintoandar.fact_listing_price_changes p_rent
        ON (p_rent.sk_house_listing / 1000)::BIGINT = lbc.id_house 
    LEFT JOIN dw_sale.fact_listing_price_changes p_sale
        ON p_sale.sk_house = lbc.id_house
    LEFT JOIN dw_public.dim_date dd
        ON p_sale.sk_price_started_date = dd.sk_date
    WHERE
        SUBSTRING(p_rent.sk_house_listing::STRING, 10) > '000' -- Excluir casos de imóveis em edição
),

first_listing AS (
    SELECT
        id_house,
        UPPER(business_context) AS business_context,
        dt_price_updated,
        price,
        status    
    FROM listings
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_house, business_context ORDER BY dt_price_updated ASC) = 1
),

relisting AS (
    SELECT 
        dhl.id_house,
        'RENT' AS business_context,
        ts_status_start AS dt_price_updated,
        dhl.house_rent AS price,
        'RELISTING' AS status
    FROM listings bl
    JOIN dw_public.fact_house_listing_status fhl
        ON bl.id_house = (fhl.sk_house_listing / 1000)::BIGINT
    JOIN dw_public.dim_house_listing dhl
        ON fhl.sk_house_listing = dhl.sk_house_listing
    WHERE
        dhl.version > 1
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY dhl.sk_house_listing ORDER BY ts_status_start ASC) = 1        
)
    
SELECT 
    id_house,
    business_context,
    dt_price_updated,
    price,
    status
FROM first_listing
    
UNION
    
SELECT 
    id_house,
    business_context,
    dt_price_updated,
    price,
    status
FROM relisting