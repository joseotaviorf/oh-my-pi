WITH sale AS (
    WITH aux_fs AS (
        SELECT
            sk_sale_listing,
            MIN(ts_load) AS min_load
        FROM dw_sale.fact_listings
        GROUP BY 1
        ),

    first_load AS (
        SELECT
            SUBSTRING(fl.sk_sale_listing,0,9) AS id_house,
            fl.sk_sale_listing AS sk_house_listing,
            'FS' AS listing_category,
            fl.price
        FROM dw_sale.fact_listings fl
        INNER JOIN aux_fs afs
            ON fl.sk_sale_listing = afs.sk_sale_listing
            AND afs.min_load = fl.ts_load
        )

    SELECT
        fl.id_house,
        'SALE' AS business_context,
        COALESCE(CONCAT(fls.status_history,' - ',fls.status_change_reason),fls.status_history) AS status,
        fls.ts_status_started,
        fl.price
    FROM dw_sale.fact_listing_status fls
    INNER JOIN first_load fl
        ON fls.sk_sale_listing = fl.sk_house_listing
),

rent AS (
    WITH aux_fr AS (
        SELECT
            id_house_listing,
            min(dt_day) AS min_day
        FROM datalake_rental_historical_follow_up.house_listings_daily_info
        GROUP BY 1
        ),

    daily_info AS (
        SELECT
            di.dt_day,
            di.id_house,
            di.id_house_listing,
            di.listing_category,
            di.rent
        FROM datalake_rental_historical_follow_up.house_listings_daily_info di
        INNER JOIN aux_fr a
            ON a.id_house_listing = di.id_house_listing
            AND a.min_day = di.dt_day
        WHERE
            country_code = 'BR'
        )

    SELECT
        SUBSTRING(sk_house_listing,0,9) AS id_house,
        'RENT' AS business_context,
        COALESCE(CONCAT(fhls.status_history,' - ', fhls.status_change_reason),fhls.status_history) AS status,
        fhls.ts_status_start AS ts_status_started,
        di.rent AS price
    FROM dw_public.fact_house_listing_status fhls
    LEFT JOIN daily_info di
        ON fhls.sk_house_listing = di.id_house_listing
)

SELECT
    *
FROM sale

UNION

SELECT
    *
FROM rent
