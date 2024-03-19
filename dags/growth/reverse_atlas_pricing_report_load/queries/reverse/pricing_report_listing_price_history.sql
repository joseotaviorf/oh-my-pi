WITH rental AS (
    SELECT
        dhl.id_house,
        dhl.sk_house_listing,
        'RENT' AS business_context,
        dhl.house_rent AS price,
        DATE(fhl.ts_status_start) AS dt_price_changed,
        CASE WHEN version = 1 THEN 'First Listing' ELSE 'Relisting' END AS status,
        ROW_NUMBER() OVER(PARTITION BY dhl.sk_house_listing ORDER BY ts_status_start) AS rn
    FROM dw_public.fact_house_listing_status fhl
    INNER JOIN dw_public.dim_house_listing dhl ON fhl.sk_house_listing = dhl.sk_house_listing
    WHERE
        dhl.version > 0
        AND fhl.status_history IN ('PUBLISHED', 'publicado')
),
listing_version AS (
    
    SELECT
        id_house,
        business_context,
        price,
        dt_price_changed,
        status
    FROM rental 
    WHERE 
        rn = 1
    
    UNION
    
    SELECT
        sk_house AS id_house,
        'SALE' AS business_context,
        price,
        dd.date AS dt_price_changed,
        'First Listing' AS status
    FROM dw_sale.fact_listing_price_changes f
    INNER JOIN dw_public.dim_date dd ON f.sk_price_started_date = dd.sk_date
    WHERE
        is_first_price = TRUE
),
prices AS (
    SELECT
        sk_house AS id_house,
        sk_price_started_date,
        price,
        'SALE' AS business_context
    FROM
        dw_sale.fact_listing_price_changes
    UNION ALL
    SELECT
        CAST(SUBSTRING(sk_house_listing::STRING, 9) AS BIGINT) AS id_house,
        sk_price_started_date,
        rent AS price,
        'RENT' AS business_context
    FROM
        dw_quintoandar.fact_listing_price_changes
),
price_updated AS (
    SELECT 
        id_house,
        business_context,
        dd.date AS dt_price_changed,
        price,
        'Last Price Update' AS status,
        ROW_NUMBER() OVER(PARTITION BY id_house, business_context ORDER BY sk_price_started_date DESC) AS rn_order,
        ROW_NUMBER() OVER(PARTITION BY id_house, business_context ORDER BY sk_price_started_date) AS rn_fl
    FROM prices b
    INNER JOIN dw_public.dim_date dd ON b.sk_price_started_date = dd.sk_date
),
negotiation AS (
    SELECT
        f.sk_house_listing / 1000 AS id_house,
        'RENT' AS business_context,
        dc.rent AS price,
        DATE(dc.ts_signature) AS dt_price_changed,
        'Contract Signed' AS status
    FROM dw_public.fact_house_listings f
    INNER JOIN dw_public.dim_contract dc ON f.sk_contract = dc.sk_contract
    WHERE
        dc.ts_signature IS NOT NULL
        
    UNION 
    
    SELECT
        fo.sk_house AS id_house,
        'SALE' AS business_context,
        ds.sale_price_agreed AS price,
        dd.date AS dt_price_changed,
        'CCV Signed' AS status
    FROM dw_sale.fact_offers fo
    INNER JOIN dw_sale.dim_sale_agreement ds ON fo.sk_offer = ds.sk_offer
    INNER JOIN dw_public.dim_date dd ON dd.sk_date = fo.sk_sale_agreement_signed_date
    WHERE
        fo.sk_sale_agreement_signed_date > 0
)
SELECT 
    id_house,
    business_context,
    price,
    dt_price_changed,
    status
FROM listing_version  

UNION 

SELECT
    id_house,
    business_context,
    price,
    dt_price_changed,
    status
FROM price_updated
WHERE rn_order = 1 AND rn_fl > 1

UNION 

SELECT
    id_house,
    business_context,
    price,
    dt_price_changed,
    status
FROM negotiation