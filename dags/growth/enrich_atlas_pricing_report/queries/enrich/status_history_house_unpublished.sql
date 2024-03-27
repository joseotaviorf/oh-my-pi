SELECT 
    id_house,
    UPPER(business_context) AS business_context,
    FROM_UNIXTIME(ts_revision / 1000) AS dt_price_updated,
    NULL::FLOAT AS price,
    status
FROM datalake_ebdb_clean.listing_business_context_aud lbc
INNER JOIN datalake_ebdb_clean.user_revision_entity ure
    ON lbc.rev = ure.id
WHERE
    lbc.status = 'UNPUBLISHED'