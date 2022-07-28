SELECT
    lbc.id AS id_listing_business_context,
    lrm.id AS id_listing_rent_model,
    lbc.id_house,
    COALESCE(lrm.rental_administrator, 'QUINTOANDAR') AS rental_administrator,
    lbc.status,
    lbc.status_reason,
    lbc.ts_first_publication,
    lbc.ts_last_publication,
    lbc.ts_created,
    lbc.ts_updated
FROM
    datalake_ebdb_clean.listing_business_context AS lbc
LEFT JOIN
    datalake_ebdb_clean.listing_rent_model AS lrm
        ON lbc.id = lrm.id_listing_business_context
WHERE
    lbc.business_context = 'RENT'