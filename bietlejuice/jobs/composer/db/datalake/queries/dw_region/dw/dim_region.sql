WITH
first_house AS (
    SELECT
        h.id_region,
        MIN(h.dt_creation) AS ts_first_house_created
    FROM datalake_ebdb_listing.house h
    WHERE h.id_region IS NOT NULL
    GROUP BY h.id_region
),
first_booking AS (
    SELECT
        h.id_region,
        MIN(b.dt_booking) AS dt_first_booking
    FROM datalake_booking.booking b
    LEFT JOIN datalake_ebdb_listing.house h
        ON b.id_house = h.id
    LEFT JOIN datalake_region.region r
        ON r.id = h.id_region
    GROUP BY h.id_region
)
SELECT
    CAST(r.id AS INT) AS sk_region,
    CAST(r.id AS INT) AS id, -- id_region,
    r.id_country,
    CAST(r.id_macro_region AS INT) AS macro_id,
    CAST(r.id_city AS INT) AS city_id,
    r.level,
    r.name,
    r.macro_region_name AS macro_name,
    r.city_name,
    r.city_group,
    r.city_ddd,
    r.region_code,
    r.region_code_deprecated,
    r.region_code_inspector,
    r.short_region_name,
    r.greater_region,
    r.regional,
    r.regional_deprecated,
    r.regional_inspection,
    r.tier,
    r.country_name,
    CAST(fb.dt_first_booking AS TIMESTAMP) AS dt_first_booking, -- date
    fh.ts_first_house_created AS dt_first_property_created,
    r.ts_created AS dt_created,
    r.ts_updated AS dt_updated,
    now() AS dt_timestamp -- ts_load
FROM datalake_region.region r
LEFT JOIN first_house fh
    ON fh.id_region = r.id
LEFT JOIN first_booking fb
    ON fb.id_region = r.id
WHERE r.level IN ('SubRegiao', 'Cidade')
