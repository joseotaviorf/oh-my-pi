SELECT
    lbc.id AS id_listing_business_context,
    lrm.id AS id_listing_rent_model,
    lbc.id_house,
    COALESCE(ch.country_code, 'Undefined') AS country_code,
    COALESCE(lrm.rental_administrator, 'QUINTOANDAR') AS rental_administrator,
    lbc.status,
    lbc.status_reason,
    lbc.ts_first_publication,
    lbc.ts_last_publication,
    CAST(FROM_UNIXTIME(ure.ts_revision/1000) AS TIMESTAMP) AS ts_administrator_changed,
    lbc.ts_created,
    lbc.ts_updated
FROM
    datalake_ebdb_clean.listing_business_context AS lbc
LEFT JOIN
    datalake_ebdb_clean.listing_rent_model AS lrm
        ON lbc.id = lrm.id_listing_business_context
LEFT JOIN datalake_ebdb_clean.listing_rent_model_aud AS aud
        ON aud.id_listing_business_context = lbc.id
        AND aud.rental_administrator = lrm.rental_administrator
        AND aud.rev_type = 1
LEFT JOIN
    datalake_ebdb_clean.user_revision_entity AS ure 
        ON aud.rev = ure.id
LEFT JOIN
    datalake_ebdb_country.house AS ch
        ON ch.id_house = lbc.id_house
WHERE
    lbc.business_context = 'RENT'