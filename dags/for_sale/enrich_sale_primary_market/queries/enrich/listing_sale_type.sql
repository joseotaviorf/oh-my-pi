-- Latest SALE listing per house. sale_type from LSM, else boolean is_primary_market.
SELECT
    id_house,
    sale_type
FROM (
    SELECT
        lbc.id_house,
        CASE
            WHEN lsm.sale_type IS NOT NULL THEN lsm.sale_type
            WHEN lsm.is_primary_market = TRUE THEN 'PRIMARY'
            ELSE 'SECONDARY'
        END AS sale_type,
        ROW_NUMBER() OVER (PARTITION BY lbc.id_house ORDER BY lbc.ts_updated DESC) AS _w
    FROM
        datalake_ebdb_clean.listing_business_context AS lbc
    INNER JOIN
        datalake_ebdb_clean.listing_sale_model AS lsm
            ON lbc.id = lsm.id_listing_business_context
    WHERE
        lbc.business_context = 'SALE'
) AS _t
WHERE
    _w = 1
