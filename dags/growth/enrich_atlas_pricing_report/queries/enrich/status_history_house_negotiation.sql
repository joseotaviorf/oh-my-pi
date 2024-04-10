WITH negotiation_status AS (
    SELECT DISTINCT
        lbc.id_house,
        UPPER(lbc.business_context) AS business_context,
        'NEGOTIATED' AS status,
        CASE
            WHEN lbc.business_context = 'RENT' AND dc.ts_signature IS NOT NULL THEN dc.ts_signature
            WHEN lbc.business_context = 'SALE' AND fo.sk_sale_agreement_signed_date > 0 THEN dd.date
        END AS ts_status_started,
        CASE
            WHEN lbc.business_context = 'RENT' AND dc.ts_signature IS NOT NULL THEN dc.rent
            WHEN lbc.business_context = 'SALE' AND fo.sk_sale_agreement_signed_date > 0 THEN ds.sale_price_agreed
        END AS price
    FROM datalake_ebdb_clean.listing_business_context lbc
    LEFT JOIN dw_public.fact_house_listings f
        ON lbc.id_house = SUBSTRING(f.sk_house_listing,0,9)
    LEFT JOIN dw_public.dim_contract dc
        ON f.sk_contract = dc.sk_contract
        AND dc.ts_signature IS NOT NULL
    LEFT JOIN dw_sale.fact_offers fo
        ON fo.sk_house = lbc.id_house
        AND fo.sk_sale_agreement_signed_date > 0
    LEFT JOIN dw_sale.dim_sale_agreement ds
        ON fo.sk_offer = ds.sk_offer
    LEFT JOIN dw_public.dim_date dd
        ON dd.sk_date = fo.sk_sale_agreement_signed_date
)

SELECT
    *
FROM negotiation_status
WHERE
    ts_status_started IS NOT NULL
