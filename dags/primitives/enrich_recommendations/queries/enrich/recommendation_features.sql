WITH  idx_lpvs AS (
    SELECT
        rec.id_recset,
        rec.id_user,
        MAX(ulpvs.timestamp) AS user_lpvs_ts
    FROM
        datalake_recommendations.recommendation AS rec
    JOIN
        wonka.user_sale_listing_page_viewed_cross_devices ulpvs
        ON ulpvs.id = rec.id_user
            AND ulpvs.timestamp < rec.ts_rec_created
    WHERE
        MAKE_DATE(YEAR(timestamp), MONTH(timestamp), DAY(timestamp)) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
    GROUP BY 1, 2
),

 idx_lpvr AS (
    SELECT
        rec.id_recset,
        rec.id_user,
        MAX(ulpvr.timestamp) AS user_lpvr_ts
    FROM
        datalake_recommendations.recommendation AS rec
    JOIN
        wonka.user_listing_page_viewed_cross_devices ulpvr
        ON ulpvr.id = rec.id_user
            AND ulpvr.timestamp < rec.ts_rec_created
    WHERE
        MAKE_DATE(YEAR(timestamp), MONTH(timestamp), DAY(timestamp)) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
    GROUP BY 1, 2
),

 idx_house AS (
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
), idx_sfs AS (
    SELECT
        rec.id_recset,
        rec.id_user,
        MAX(uasfs.timestamp) AS user_sfs_ts
    FROM
        datalake_recommendations.recommendation AS rec
    LEFT JOIN
        wonka.user_sale_agg_search_filters uasfs
        ON rec.id_user = uasfs.id
            AND uasfs.timestamp < rec.ts_rec_created
    WHERE
        MAKE_DATE(YEAR(timestamp), MONTH(timestamp), DAY(timestamp)) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
    GROUP BY 1, 2
), idx_sfr AS (
    SELECT
        rec.id_recset,
        rec.id_user,
        MAX(uasfr.timestamp) AS user_sfr_ts
    FROM
        datalake_recommendations.recommendation AS rec
    LEFT JOIN
        wonka.user_agg_search_filters uasfr
        ON rec.id_user = uasfr.id
            AND uasfr.timestamp < rec.ts_rec_created
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
        idx_lpvs.user_lpvs_ts,
        idx_lpvr.user_lpvr_ts,
        idx_house.house_ts,
        idx_amenities.amenities_ts,
        idx_condo_amenities.condo_amenities_ts,
        idx_sfs.user_sfs_ts,
        idx_sfr.user_sfr_ts,
        rec.dt_rec_received
    FROM
        datalake_recommendations.recommendation rec
    LEFT JOIN
        idx_lpvs
        ON idx_lpvs.id_user = rec.id_user
            AND idx_lpvs.id_recset = rec.id_recset
    LEFT JOIN
        idx_lpvr
        ON idx_lpvr.id_user = rec.id_user
            AND idx_lpvr.id_recset = rec.id_recset
    LEFT JOIN
        idx_house
        ON idx_house.id_item = rec.id_item
            AND idx_house.id_recset = rec.id_recset
    LEFT JOIN idx_amenities
        ON idx_amenities.id_item = rec.id_item
            AND idx_amenities.id_recset = rec.id_recset
    LEFT JOIN
        idx_condo_amenities
        ON idx_condo_amenities.id_item = rec.id_item
            AND idx_condo_amenities.id_recset = rec.id_recset
    LEFT JOIN
        idx_sfs
        ON idx_sfs.id_user = rec.id_user
            AND idx_sfs.id_recset = rec.id_recset
        LEFT JOIN
        idx_sfr
        ON idx_sfr.id_user = rec.id_user
            AND idx_sfr.id_recset = rec.id_recset
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
    --user lpv sale
    ulpvs.sale_listing_page_viewed_sale_price__avg_over_15_events_row_windows AS user__sale_listing_page_viewed_sale_price__avg_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_sale_price__stddev_pop_over_15_events_row_windows AS user__sale_listing_page_viewed_sale_price__stddev_pop_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_bedroom_count__avg_over_15_events_row_windows AS user__sale_listing_page_viewed_bedroom_count__avg_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_bedroom_count__stddev_pop_over_15_events_row_windows AS user__sale_listing_page_viewed_bedroom_count__stddev_pop_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_total_area__avg_over_15_events_row_windows AS user__sale_listing_page_viewed_total_area__avg_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_total_area__stddev_pop_over_15_events_row_windows AS user__sale_listing_page_viewed_total_area__stddev_pop_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_bathroom_count__avg_over_15_events_row_windows AS user__sale_listing_page_viewed_bathroom_count__avg_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_bathroom_count__stddev_pop_over_15_events_row_windows AS user__sale_listing_page_viewed_bathroom_count__stddev_pop_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_condominium_per_month__avg_over_15_events_row_windows AS user__sale_listing_page_viewed_condominium_per_month__avg_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_condominium_per_month__stddev_pop_over_15_events_row_windows AS user__sale_listing_page_viewed_condominium_per_month__stddev_pop_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_floor__avg_over_15_events_row_windows AS user__sale_listing_page_viewed_floor__avg_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_floor__stddev_pop_over_15_events_row_windows AS user__sale_listing_page_viewed_floor__stddev_pop_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_iptu_per_month__avg_over_15_events_row_windows AS user__sale_listing_page_viewed_iptu_per_month__avg_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_iptu_per_month__stddev_pop_over_15_events_row_windows AS user__sale_listing_page_viewed_iptu_per_month__stddev_pop_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_sale_price_over_area__avg_over_15_events_row_windows AS user__sale_listing_page_viewed_sale_price_over_area__avg_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_sale_price_over_area__stddev_pop_over_15_events_row_windows AS user__sale_listing_page_viewed_sale_price_over_area__stddev_pop_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_suite_count__avg_over_15_events_row_windows AS user__sale_listing_page_viewed_suite_count__avg_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_suite_count__stddev_pop_over_15_events_row_windows AS user__sale_listing_page_viewed_suite_count__stddev_pop_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_has_elevator__avg_over_15_events_row_windows AS user__sale_listing_page_viewed_has_elevator__avg_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_has_air_conditioning__avg_over_15_events_row_windows AS user__sale_listing_page_viewed_has_air_conditioning__avg_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_has_bedroom_cabinets__avg_over_15_events_row_windows AS user__sale_listing_page_viewed_has_bedroom_cabinets__avg_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_has_fridge__avg_over_15_events_row_windows AS user__sale_listing_page_viewed_has_fridge__avg_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_has_kitchen_cabinets__avg_over_15_events_row_windows AS user__sale_listing_page_viewed_has_kitchen_cabinets__avg_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_has_oven__avg_over_15_events_row_windows AS user__sale_listing_page_viewed_has_oven__avg_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_has_pool__avg_over_15_events_row_windows AS user__sale_listing_page_viewed_has_pool__avg_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_is_furnished__avg_over_15_events_row_windows AS user__sale_listing_page_viewed_is_furnished__avg_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_is_penthouse__avg_over_15_events_row_windows AS user__sale_listing_page_viewed_is_penthouse__avg_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_parking_slots_count__avg_over_15_events_row_windows AS user__sale_listing_page_viewed_parking_slots_count__avg_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_parking_slots_count__stddev_pop_over_15_events_row_windows AS user__sale_listing_page_viewed_parking_slots_count__stddev_pop_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_is_apartment__avg_over_15_events_row_windows AS user__sale_listing_page_viewed_is_apartment__avg_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_is_studio__avg_over_15_events_row_windows AS user__sale_listing_page_viewed_is_studio__avg_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_is_house__avg_over_15_events_row_windows AS user__sale_listing_page_viewed_is_house__avg_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_is_house_condominium__avg_over_15_events_row_windows AS user__sale_listing_page_viewed_is_house_condominium__avg_over_15_events_row_windows,
    ulpvs.sale_listing_page_viewed_city__collect_set_over_15_events_row_windows AS user__sale_listing_page_viewed_city__collect_set_over_15_events_row_windows,
    --user lpv rent
    ulpvr.listing_page_viewed_rent_per_month__avg_over_15_events_row_windows AS user__listing_page_viewed_rent_per_month__avg_over_15_events_row_windows,
    ulpvr.listing_page_viewed_rent_per_month__stddev_pop_over_15_events_row_windows AS user__listing_page_viewed_rent_per_month__stddev_pop_over_15_events_row_windows,
    ulpvr.listing_page_viewed_bedroom_count__avg_over_15_events_row_windows AS user__listing_page_viewed_bedroom_count__avg_over_15_events_row_windows,
    ulpvr.listing_page_viewed_bedroom_count__stddev_pop_over_15_events_row_windows AS user__listing_page_viewed_bedroom_count__stddev_pop_over_15_events_row_windows,
    ulpvr.listing_page_viewed_total_area__avg_over_15_events_row_windows AS user__listing_page_viewed_total_area__avg_over_15_events_row_windows,
    ulpvr.listing_page_viewed_total_area__stddev_pop_over_15_events_row_windows AS user__listing_page_viewed_total_area__stddev_pop_over_15_events_row_windows,
    ulpvr.listing_page_viewed_bathroom_count__avg_over_15_events_row_windows AS user__listing_page_viewed_bathroom_count__avg_over_15_events_row_windows,
    ulpvr.listing_page_viewed_bathroom_count__stddev_pop_over_15_events_row_windows AS user__listing_page_viewed_bathroom_count__stddev_pop_over_15_events_row_windows,
    ulpvr.listing_page_viewed_condominium_per_month__avg_over_15_events_row_windows AS user__listing_page_viewed_condominium_per_month__avg_over_15_events_row_windows,
    ulpvr.listing_page_viewed_condominium_per_month__stddev_pop_over_15_events_row_windows AS user__listing_page_viewed_condominium_per_month__stddev_pop_over_15_events_row_windows,
    ulpvr.listing_page_viewed_floor__avg_over_15_events_row_windows AS user__listing_page_viewed_floor__avg_over_15_events_row_windows,
    ulpvr.listing_page_viewed_floor__stddev_pop_over_15_events_row_windows AS user__listing_page_viewed_floor__stddev_pop_over_15_events_row_windows,
    ulpvr.listing_page_viewed_iptu_per_month__avg_over_15_events_row_windows AS user__listing_page_viewed_iptu_per_month__avg_over_15_events_row_windows,
    ulpvr.listing_page_viewed_iptu_per_month__stddev_pop_over_15_events_row_windows AS user__listing_page_viewed_iptu_per_month__stddev_pop_over_15_events_row_windows,
    ulpvr.listing_page_viewed_rent_over_area__avg_over_15_events_row_windows AS user__listing_page_viewed_rent_over_area__avg_over_15_events_row_windows,
    ulpvr.listing_page_viewed_rent_over_area__stddev_pop_over_15_events_row_windows AS user__listing_page_viewed_rent_over_area__stddev_pop_over_15_events_row_windows,
    ulpvr.listing_page_viewed_suite_count__avg_over_15_events_row_windows AS user__listing_page_viewed_suite_count__avg_over_15_events_row_windows,
    ulpvr.listing_page_viewed_suite_count__stddev_pop_over_15_events_row_windows AS user__listing_page_viewed_suite_count__stddev_pop_over_15_events_row_windows,
    ulpvr.listing_page_viewed_has_elevator__avg_over_15_events_row_windows AS user__listing_page_viewed_has_elevator__avg_over_15_events_row_windows,
    ulpvr.listing_page_viewed_has_air_conditioning__avg_over_15_events_row_windows AS user__listing_page_viewed_has_air_conditioning__avg_over_15_events_row_windows,
    ulpvr.listing_page_viewed_has_bedroom_cabinets__avg_over_15_events_row_windows AS user__listing_page_viewed_has_bedroom_cabinets__avg_over_15_events_row_windows,
    ulpvr.listing_page_viewed_has_fridge__avg_over_15_events_row_windows AS user__listing_page_viewed_has_fridge__avg_over_15_events_row_windows,
    ulpvr.listing_page_viewed_has_kitchen_cabinets__avg_over_15_events_row_windows AS user__listing_page_viewed_has_kitchen_cabinets__avg_over_15_events_row_windows,
    ulpvr.listing_page_viewed_has_oven__avg_over_15_events_row_windows AS user__listing_page_viewed_has_oven__avg_over_15_events_row_windows,
    ulpvr.listing_page_viewed_has_pool__avg_over_15_events_row_windows AS user__listing_page_viewed_has_pool__avg_over_15_events_row_windows,
    ulpvr.listing_page_viewed_is_furnished__avg_over_15_events_row_windows AS user__listing_page_viewed_is_furnished__avg_over_15_events_row_windows,
    ulpvr.listing_page_viewed_is_penthouse__avg_over_15_events_row_windows AS user__listing_page_viewed_is_penthouse__avg_over_15_events_row_windows,
    ulpvr.listing_page_viewed_parking_slots_count__avg_over_15_events_row_windows AS user__listing_page_viewed_parking_slots_count__avg_over_15_events_row_windows,
    ulpvr.listing_page_viewed_parking_slots_count__stddev_pop_over_15_events_row_windows AS user__listing_page_viewed_parking_slots_count__stddev_pop_over_15_events_row_windows,
    ulpvr.listing_page_viewed_is_apartment__avg_over_15_events_row_windows AS user__listing_page_viewed_is_apartment__avg_over_15_events_row_windows,
    ulpvr.listing_page_viewed_is_studio__avg_over_15_events_row_windows AS user__listing_page_viewed_is_studio__avg_over_15_events_row_windows,
    ulpvr.listing_page_viewed_is_house__avg_over_15_events_row_windows AS user__listing_page_viewed_is_house__avg_over_15_events_row_windows,
    ulpvr.listing_page_viewed_is_house_condominium__avg_over_15_events_row_windows AS user__listing_page_viewed_is_house_condominium__avg_over_15_events_row_windows,
    ulpvr.listing_page_viewed_city__collect_set_over_15_events_row_windows AS user__listing_page_viewed_city__collect_set_over_15_events_row_windows,
    --user filter sale
    uasfs.sale_filter_sale_price_min__avg_over_30_days_rolling_windows AS user__sale_filter_sale_price_min__avg_over_30_days_rolling_windows,
    uasfs.sale_filter_sale_price_min__stddev_pop_over_30_days_rolling_windows AS user__sale_filter_sale_price_min__stddev_pop_over_30_days_rolling_windows,
    uasfs.sale_filter_sale_price_max__avg_over_30_days_rolling_windows AS user__sale_filter_sale_price_max__avg_over_30_days_rolling_windows,
    uasfs.sale_filter_sale_price_max__stddev_pop_over_30_days_rolling_windows AS user__sale_filter_sale_price_max__stddev_pop_over_30_days_rolling_windows,
    uasfs.sale_filter_value_area_min__avg_over_30_days_rolling_windows AS user__sale_filter_value_area_min__avg_over_30_days_rolling_windows,
    uasfs.sale_filter_value_area_min__stddev_pop_over_30_days_rolling_windows AS user__sale_filter_value_area_min__stddev_pop_over_30_days_rolling_windows,
    uasfs.sale_filter_value_area_max__avg_over_30_days_rolling_windows AS user__sale_filter_value_area_max__avg_over_30_days_rolling_windows,
    uasfs.sale_filter_value_area_max__stddev_pop_over_30_days_rolling_windows AS user__sale_filter_value_area_max__stddev_pop_over_30_days_rolling_windows,
    uasfs.sale_filter_house_type_count__avg_over_30_days_rolling_windows AS user__sale_filter_house_type_count__avg_over_30_days_rolling_windows,
    uasfs.sale_filter_house_type_count__stddev_pop_over_30_days_rolling_windows AS user__sale_filter_house_type_count__stddev_pop_over_30_days_rolling_windows,
    uasfs.sale_filter_list_rooms_count__avg_over_30_days_rolling_windows AS user__sale_filter_list_rooms_count__avg_over_30_days_rolling_windows,
    uasfs.sale_filter_list_rooms_count__stddev_pop_over_30_days_rolling_windows AS user__sale_filter_list_rooms_count__stddev_pop_over_30_days_rolling_windows,
    uasfs.sale_filter_list_parking_count__avg_over_30_days_rolling_windows AS user__sale_filter_list_parking_count__avg_over_30_days_rolling_windows,
    uasfs.sale_filter_list_parking_count__stddev_pop_over_30_days_rolling_windows AS user__sale_filter_list_parking_count__stddev_pop_over_30_days_rolling_windows,
    uasfs.sale_filter_list_apartment_count__avg_over_30_days_rolling_windows AS user__sale_filter_list_apartment_count__avg_over_30_days_rolling_windows,
    uasfs.sale_filter_list_apartment_count__stddev_pop_over_30_days_rolling_windows AS user__sale_filter_list_apartment_count__stddev_pop_over_30_days_rolling_windows,
    uasfs.sale_filter_list_condo_count__avg_over_30_days_rolling_windows AS user__sale_filter_list_condo_count__avg_over_30_days_rolling_windows,
    uasfs.sale_filter_list_condo_count__stddev_pop_over_30_days_rolling_windows AS user__sale_filter_list_condo_count__stddev_pop_over_30_days_rolling_windows,
    uasfs.sale_filter_value_furnished__max_over_30_days_rolling_windows AS user__sale_filter_value_furnished__max_over_30_days_rolling_windows,
    uasfs.sale_filter_value_metro__max_over_30_days_rolling_windows AS user__sale_filter_value_metro__max_over_30_days_rolling_windows,
    uasfs.sale_filter_value_pets__max_over_30_days_rolling_windows AS user__sale_filter_value_pets__max_over_30_days_rolling_windows,
    --user filter rent
    uasfr.filter_value_price_min__avg_over_30_days_rolling_windows AS user__filter_value_price_min__avg_over_30_days_rolling_windows,
    uasfr.filter_value_price_min__stddev_pop_over_30_days_rolling_windows AS user__filter_value_price_min__stddev_pop_over_30_days_rolling_windows,
    uasfr.filter_value_price_max__avg_over_30_days_rolling_windows AS user__filter_value_price_max__avg_over_30_days_rolling_windows,
    uasfr.filter_value_price_max__stddev_pop_over_30_days_rolling_windows AS user__filter_value_price_max__stddev_pop_over_30_days_rolling_windows,
    uasfr.filter_value_area_min__avg_over_30_days_rolling_windows AS user__filter_value_area_min__avg_over_30_days_rolling_windows,
    uasfr.filter_value_area_min__stddev_pop_over_30_days_rolling_windows AS user__filter_value_area_min__stddev_pop_over_30_days_rolling_windows,
    uasfr.filter_value_area_max__avg_over_30_days_rolling_windows AS user__filter_value_area_max__avg_over_30_days_rolling_windows,
    uasfr.filter_value_area_max__stddev_pop_over_30_days_rolling_windows AS user__filter_value_area_max__stddev_pop_over_30_days_rolling_windows,
    uasfr.filter_house_type_count__avg_over_30_days_rolling_windows AS user__filter_house_type_count__avg_over_30_days_rolling_windows,
    uasfr.filter_house_type_count__stddev_pop_over_30_days_rolling_windows AS user__filter_house_type_count__stddev_pop_over_30_days_rolling_windows,
    uasfr.filter_list_rooms_count__avg_over_30_days_rolling_windows AS user__filter_list_rooms_count__avg_over_30_days_rolling_windows,
    uasfr.filter_list_rooms_count__stddev_pop_over_30_days_rolling_windows AS user__filter_list_rooms_count__stddev_pop_over_30_days_rolling_windows,
    uasfr.filter_list_parking_count__avg_over_30_days_rolling_windows AS user__filter_list_parking_count__avg_over_30_days_rolling_windows,
    uasfr.filter_list_parking_count__stddev_pop_over_30_days_rolling_windows AS user__filter_list_parking_count__stddev_pop_over_30_days_rolling_windows,
    uasfr.filter_list_apartment_count__avg_over_30_days_rolling_windows AS user__filter_list_apartment_count__avg_over_30_days_rolling_windows,
    uasfr.filter_list_apartment_count__stddev_pop_over_30_days_rolling_windows AS user__filter_list_apartment_count__stddev_pop_over_30_days_rolling_windows,
    uasfr.filter_list_condo_count__avg_over_30_days_rolling_windows AS user__filter_list_condo_count__avg_over_30_days_rolling_windows,
    uasfr.filter_list_condo_count__stddev_pop_over_30_days_rolling_windows AS user__filter_list_condo_count__stddev_pop_over_30_days_rolling_windows,
    uasfr.filter_value_furnished__max_over_30_days_rolling_windows AS user__filter_value_furnished__max_over_30_days_rolling_windows,
    uasfr.filter_value_metro__max_over_30_days_rolling_windows AS user__filter_value_metro__max_over_30_days_rolling_windows,
    uasfr.filter_value_pets__max_over_30_days_rolling_windows AS user__filter_value_pets__max_over_30_days_rolling_windows,
    --house main
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
LEFT JOIN wonka.user_sale_listing_page_viewed_cross_devices ulpvs
  ON ulpvs.id = idx.id_user
  AND ulpvs.timestamp = idx.user_lpvs_ts
LEFT JOIN wonka.user_listing_page_viewed_cross_devices ulpvr
  ON ulpvr.id = idx.id_user
  AND ulpvr.timestamp = idx.user_lpvr_ts
LEFT JOIN wonka.house_main h
  ON h.id = idx.id_house
  AND h.timestamp = idx.house_ts
LEFT JOIN wonka.user_sale_agg_search_filters uasfs
  ON uasfs.id = idx.id_user
    AND uasfs.timestamp = idx.user_sfs_ts
LEFT JOIN wonka.user_agg_search_filters uasfr
  ON uasfr.id = idx.id_user
    AND uasfr.timestamp = idx.user_sfr_ts
LEFT JOIN wonka.house_amenities ha
  ON ha.id = idx.id_house
  AND ha.timestamp = idx.amenities_ts
LEFT JOIN wonka.house_condo_amenities hca
  ON hca.id = idx.id_house
  AND hca.timestamp = idx.condo_amenities_ts
