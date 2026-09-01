-- Latest SALE listing per house. sale_type from LSM, else boolean is_primary_market.
WITH listing_sale_type_latest AS (
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
)
SELECT
    lst.id_house,
    lst.sale_type,
    -- id_development: offer-created unit first, else the typology "shell" listing.
    COALESCE(dtu.id_development, dt.id_development) AS id_development
FROM
    listing_sale_type_latest AS lst
LEFT JOIN
    datalake_ebdb_clean.development_typology_unit AS dtu
        ON dtu.id_house = lst.id_house
LEFT JOIN
    datalake_ebdb_clean.house AS h
        ON h.id = lst.id_house
LEFT JOIN
    datalake_ebdb_clean.development_typology AS dt
        ON dt.id = h.id_development_typology
