-- One SALE listing per house (id_house is unique after business_context = SALE).
-- sale_type from LSM enum (NULL -> SECONDARY).
-- Excludes old primary-market tests (is_primary_market = TRUE).
-- min_price/max_price come from the same listing_sale_model row.
SELECT
    lbc.id_house,
    CASE
        WHEN lsm.sale_type IS NULL THEN 'SECONDARY'
        ELSE lsm.sale_type
    END AS sale_type,
    lsm.min_price,
    lsm.max_price
FROM
    datalake_ebdb_clean.listing_business_context AS lbc
INNER JOIN
    datalake_ebdb_clean.listing_sale_model AS lsm
        ON lbc.id = lsm.id_listing_business_context
WHERE
    lbc.business_context = 'SALE'
    AND lsm.is_primary_market != TRUE -- Filter out old primary market tests
