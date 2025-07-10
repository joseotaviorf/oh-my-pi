WITH idx_house AS (
    SELECT
        rec.id_recset,
        rec.id_item,
        MAX(h.timestamp) AS house_ts
    FROM
        datalake_recommendations.recommendation AS rec
    JOIN
        wonka.house_main h
        ON h.id = rec.id_item
            AND h.timestamp < rec.ts_rec_created
    WHERE
        MAKE_DATE(YEAR(timestamp), MONTH(timestamp), DAY(timestamp)) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
    GROUP BY 1, 2
), idx_hlbc AS (
SELECT
        rec.id_recset,
        rec.id_item,
        MAX(hlbc.timestamp) AS hlbc_ts
    FROM
        datalake_recommendations.recommendation AS rec
    JOIN
        wonka.house_listing_business_context AS hlbc
        ON hlbc.id = rec.id_item
            AND hlbc.timestamp < rec.ts_rec_created
    WHERE
        MAKE_DATE(YEAR(timestamp), MONTH(timestamp), DAY(timestamp)) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
    GROUP BY 1, 2
), idx_amenities AS (
    SELECT
        rec.id_recset,
        rec.id_item,
        MAX(ha.timestamp) AS amenities_ts
    FROM
        datalake_recommendations.recommendation AS rec
    LEFT JOIN
        wonka.house_amenities ha
        ON ha.id = rec.id_item
            AND ha.timestamp < rec.ts_rec_created
    WHERE
        MAKE_DATE(YEAR(timestamp), MONTH(timestamp), DAY(timestamp)) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
    GROUP BY 1, 2
), idx_condo_amenities AS (
    SELECT
        rec.id_recset,
        rec.id_item,
        MAX(hca.timestamp) AS condo_amenities_ts
    FROM
        datalake_recommendations.recommendation AS rec
    LEFT JOIN
        wonka.house_condo_amenities hca
        ON hca.id = rec.id_item
            AND hca.timestamp < rec.ts_rec_created
    WHERE
        MAKE_DATE(YEAR(timestamp), MONTH(timestamp), DAY(timestamp)) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
    GROUP BY 1, 2
), idx AS (
    SELECT DISTINCT
        rec.id_recset,
        rec.id_rec,
        rec.id_user,
        rec.business_context,
        rec.display_type,
        rec.id_item AS id_house,
        rec.item_rank,
        rec.ts_rec_created,
        rec.experiments,
        rec.experiments_variants,
        idx_house.house_ts,
        idx_hlbc.hlbc_ts,
        idx_amenities.amenities_ts,
        idx_condo_amenities.condo_amenities_ts,
        rec.dt_rec_received
    FROM
        datalake_recommendations.recommendation rec
    LEFT JOIN
        idx_house
        ON idx_house.id_item = rec.id_item
            AND idx_house.id_recset = rec.id_recset
    LEFT JOIN
        idx_hlbc
        ON idx_hlbc.id_item = rec.id_item
            AND idx_hlbc.id_recset = rec.id_recset
    LEFT JOIN idx_amenities
        ON idx_amenities.id_item = rec.id_item
            AND idx_amenities.id_recset = rec.id_recset
    LEFT JOIN
        idx_condo_amenities
        ON idx_condo_amenities.id_item = rec.id_item
            AND idx_condo_amenities.id_recset = rec.id_recset
    WHERE rec.dt_rec_received BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
)
SELECT DISTINCT
    -- idx
    idx.id_recset,
    idx.id_rec,
    idx.business_context,
    idx.display_type,
    idx.id_user AS user__id,
    idx.id_house AS house__id,
    idx.item_rank,
    idx.ts_rec_created,
    idx.experiments,
    idx.experiments_variants,
    --house main
    (to_unix_timestamp(idx.ts_rec_created) - to_unix_timestamp(hlbc.rent_ts_last_publication)) / 3600 AS house__rent_listing_age_hours,
    (to_unix_timestamp(idx.ts_rec_created) - to_unix_timestamp(hlbc.sale_ts_last_publication)) / 3600 AS house__sale_listing_age_hours,
    h.bathroom_count AS house__bathroom_count,
    h.bathrooms_over_area AS house__bathrooms_over_area,
    h.bedroom_count AS house__bedroom_count,
    h.bedrooms_over_area AS house__bedrooms_over_area,
    h.city AS house__city,
    h.neighborhood AS house__neighborhood,
    h.condominium_per_month AS house__condominium_per_month,
    h.has_elevator AS house__has_elevator,
    h.is_furnished AS house__is_furnished,
    h.latitude AS house__latitude,
    h.longitude AS house__longitude,
    h.parking_slots_count AS house__parking_slots_count,
    h.sale_price AS house__sale_price,
    h.sale_price_over_area AS house__sale_price_over_area,
    h.total_area AS house__total_area,
    h.type AS house__type,
    h.floor AS house__floor,
    h.iptu_per_month AS house__iptu_per_month,
    h.rent_over_area AS house__rent_over_area,
    h.total_value_per_month AS house__total_value_per_month,
    h.suite_count AS house__suite_count,
    ha.has_air_conditioning AS house__has_air_conditioning,
    ha.has_bedroom_cabinets AS house__has_bedroom_cabinets,
    ha.has_fridge AS house__has_fridge,
    ha.has_kitchen_cabinets AS house__has_kitchen_cabinets,
    ha.has_oven AS house__has_oven,
    ha.has_gas_heated_shower AS house__has_gas_heated_shower,
    h.parking_type AS house__parking_type,
    hca.has_pool AS house__has_pool,
    ha.is_penthouse AS house__is_penthouse,
    idx.dt_rec_received
FROM idx
LEFT JOIN wonka.house_main h
  ON h.id = idx.id_house
  AND h.timestamp = idx.house_ts
LEFT JOIN wonka.house_listing_business_context hlbc
  ON hlbc.id = idx.id_house
  AND hlbc.timestamp = idx.hlbc_ts
LEFT JOIN wonka.house_amenities ha
  ON ha.id = idx.id_house
  AND ha.timestamp = idx.amenities_ts
LEFT JOIN wonka.house_condo_amenities hca
  ON hca.id = idx.id_house
  AND hca.timestamp = idx.condo_amenities_ts
