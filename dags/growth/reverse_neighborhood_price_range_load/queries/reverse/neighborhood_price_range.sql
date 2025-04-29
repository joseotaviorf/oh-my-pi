SELECT
    r.id AS id_region,
    r.name AS name_region,
    MAX(rent_houses_six_months.rent) AS max_rent_price,
    AVG(rent_houses_six_months.rent) AS avg_rent_price,
    MIN(rent_houses_six_months.rent) AS min_rent_price,
    COUNT(rent_houses_six_months.rent) AS count_rents,
    MAX(sale_houses_six_months.sale_price) AS max_sale_price,
    AVG(sale_houses_six_months.sale_price) AS avg_sale_price,
    MIN(sale_houses_six_months.sale_price) AS min_sale_price,
    COUNT(sale_houses_six_months.sale_price) AS count_sales
FROM
    datalake_ebdb_clean.region AS r
LEFT JOIN (
    SELECT
        h.id_region,
        h.sale_price
    FROM
        datalake_ebdb_clean.house AS h
    INNER JOIN
        datalake_ebdb_clean.listing_business_context AS lbc
            ON lbc.id_house = h.id
            AND lbc.business_context = 'SALE'
    WHERE
        h.sale_price IS NOT NULL
        AND h.sale_price BETWEEN 10000 AND 20000000
        AND ADD_MONTHS(CAST(lbc.ts_last_publication AS DATE), 6) >= CURRENT_DATE()
) AS sale_houses_six_months
    ON r.id = sale_houses_six_months.id_region
LEFT JOIN (
    SELECT
        h.id_region,
        h.rent
    FROM
        datalake_ebdb_clean.house AS h
    INNER JOIN
        datalake_ebdb_clean.listing_business_context AS lbc
            ON lbc.id_house = h.id
            AND lbc.business_context = 'RENT'
    WHERE
        h.rent IS NOT NULL
        AND h.rent BETWEEN 200 AND 200000
        AND ADD_MONTHS(CAST(h.ts_last_publication AS DATE), 6) >= CURRENT_DATE()
) AS rent_houses_six_months
    ON r.id = rent_houses_six_months.id_region
WHERE
    r.level = 'SubRegiao'
GROUP BY
    r.id,
    r.name
