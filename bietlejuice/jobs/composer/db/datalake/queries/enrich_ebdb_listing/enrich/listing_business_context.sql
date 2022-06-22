WITH opt_out AS (
    SELECT 
        lbc_aud.id_house,
        MAX(CASE WHEN business_context = 'RENT' THEN from_unixtime(ure.ts_revision / 1000) END) AS ts_opt_out_rent,
        MAX(CASE WHEN business_context = 'SALE' THEN from_unixtime(ure.ts_revision / 1000) END) AS ts_opt_out_sale
    FROM
        datalake_ebdb_clean.listing_business_context_aud AS lbc_aud
    JOIN
        datalake_ebdb_clean.user_revision_entity AS ure
            ON ure.id = lbc_aud.rev
    WHERE
        status = 'OPTED_OUT'
        AND mod_status = 1
    GROUP BY
        1
),
revision AS (
    SELECT 
        lbc_aud.id_house,
        MIN(CASE WHEN business_context = 'RENT' THEN lbc_aud.rev END) AS first_rev_rent,
        MIN(CASE WHEN business_context = 'SALE' THEN lbc_aud.rev END) AS first_rev_sale
    FROM
        datalake_ebdb_clean.listing_business_context_aud AS lbc_aud
    GROUP BY
        1
),
registrant AS (
    SELECT 
        lbc.id_house,
        ure_rent.id_user AS user_listing_registrant_rent,
        ure_sale.id_user AS user_listing_registrant_sale
    FROM
        datalake_ebdb_clean.listing_business_context AS lbc
    LEFT JOIN
        revision AS rev
            ON rev.id_house = lbc.id_house
    LEFT JOIN
        datalake_ebdb_clean.user_revision_entity AS ure_rent
            ON ure_rent.id = rev.first_rev_rent
    LEFT JOIN
        datalake_ebdb_clean.user_revision_entity AS ure_sale
            ON ure_sale.id = rev.first_rev_sale
    GROUP BY
        1, 2, 3
)
SELECT 
    lbc.id,
    lbc.id_house,
    lbc.business_context,
    lbc.ownership,
    lbc.calculator_price,
    lbc.status,
    lbc.status_reason,
    lbc.status_closing,
    lbc.short_url,
    COALESCE(lbc.business_context = 'RENT', FALSE) AS is_rent_context,
    COALESCE(lbc.business_context = 'SALE', FALSE) AS is_sale_context,
    COALESCE(lbc.ownership = 'THIRD_PARTY', FALSE) AS is_3p_supply,
    registrant.user_listing_registrant_rent,
    registrant.user_listing_registrant_sale,
    lbc.ts_first_publication AS ts_first_listing,
    lbc.ts_last_publication AS ts_last_listing,
    opt_out.ts_opt_out_rent,
    opt_out.ts_opt_out_sale,
    lbc.ts_created,
    lbc.ts_updated
FROM
    datalake_ebdb_clean.listing_business_context AS lbc
LEFT JOIN
    opt_out
        ON lbc.id_house = opt_out.id_house
LEFT JOIN
    registrant
        ON lbc.id_house = registrant.id_hous
