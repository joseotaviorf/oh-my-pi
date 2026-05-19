WITH amenities AS (
    WITH most_recent_amenities AS (
        SELECT
            i.id_house,
            i.id_amenities,
            i.has_characteristic,
            a.slug
        FROM
            datalake_ebdb_clean.info_amenities AS i
        JOIN
            datalake_ebdb_clean.amenities AS a
                ON i.id_amenities = a.id
        QUALIFY
            ROW_NUMBER() OVER(PARTITION BY i.id_house, i.id_amenities ORDER BY i.ts_updated DESC) = 1
    )
    SELECT
        id_house,
        FILTER(COLLECT_LIST(
            CASE
                WHEN has_characteristic = TRUE THEN id_amenities
                ELSE NULL
            END
        ), x -> x IS NOT NULL) AS amenities_with,
        FILTER(COLLECT_LIST(
            CASE
                WHEN has_characteristic = FALSE THEN id_amenities
                ELSE NULL
            END
        ), x -> x IS NOT NULL) AS amenities_without
    FROM
        most_recent_amenities
    GROUP BY
        1
),
condo_amenities AS (
    WITH most_recent_condo_amenities AS (
        SELECT
            i.id_house,
            i.id_condo_amenities,
            i.has_characteristic,
            a.slug
        FROM
            datalake_ebdb_clean.info_condo_amenities AS i
        JOIN
            datalake_ebdb_clean.condo_amenities AS a
                ON i.id_condo_amenities = a.id_condo_amenity
        QUALIFY
            ROW_NUMBER() OVER(PARTITION BY i.id_house, i.id_condo_amenities ORDER BY i.ts_updated DESC) = 1
    )
    SELECT
        id_house,
        FILTER(COLLECT_LIST(
            CASE
                WHEN has_characteristic = TRUE THEN id_condo_amenities
                ELSE NULL
            END
        ), x -> x IS NOT NULL) AS condo_amenities_with,
        FILTER(COLLECT_LIST(
            CASE
                WHEN has_characteristic = FALSE THEN id_condo_amenities
                ELSE NULL
            END
        ), x -> x IS NOT NULL) AS condo_amenities_without
    FROM
        most_recent_condo_amenities
    GROUP BY
        1
)
SELECT
    COALESCE(a.id_house, ca.id_house, hmc.id_house) AS sk_house,
    hmc.maintenance_condition,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 1) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 1) THEN FALSE
        ELSE NULL
    END AS has_hot_tub,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 2) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 2) THEN FALSE
        ELSE NULL
    END AS has_blindex_box,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 3) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 3) THEN FALSE
        ELSE NULL
    END AS has_balcony,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 4) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 4) THEN FALSE
        ELSE NULL
    END AS has_stove_and_fridge,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 5) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 5) THEN FALSE
        ELSE NULL
    END AS has_private_pool,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 6) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 6) THEN FALSE
        ELSE NULL
    END AS has_private_grill,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 7) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 7) THEN FALSE
        ELSE NULL
    END AS has_bedroom_cabinet,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 8) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 8) THEN FALSE
        ELSE NULL
    END AS has_bathroom_cabinet,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 9) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 9) THEN FALSE
        ELSE NULL
    END AS has_kitchen_cabinet,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 10) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 10) THEN FALSE
        ELSE NULL
    END AS has_air_conditioner,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 11) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 11) THEN FALSE
        ELSE NULL
    END AS has_internet,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 12) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 12) THEN FALSE
        ELSE NULL
    END AS has_gas_shower,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 13) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 13) THEN FALSE
        ELSE NULL
    END AS has_pet,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 14) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 14) THEN FALSE
        ELSE NULL
    END AS has_service_room,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 15) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 15) THEN FALSE
        ELSE NULL
    END AS has_service_bathroom,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 16) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 16) THEN FALSE
        ELSE NULL
    END AS has_permanent_garage,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 17) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 17) THEN FALSE
        ELSE NULL
    END AS has_gourmet_balcony,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 18) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 18) THEN FALSE
        ELSE NULL
    END AS has_penthouse_apartment,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 19) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 19) THEN FALSE
        ELSE NULL
    END AS has_extra_reversible_bedroom,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 20) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 20) THEN FALSE
        ELSE NULL
    END AS has_stove,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 21) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 21) THEN FALSE
        ELSE NULL
    END AS has_fridge,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 22) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 22) THEN FALSE
        ELSE NULL
    END AS has_morning_sun,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 23) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 23) THEN FALSE
        ELSE NULL
    END AS has_afternoon_sun,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 24) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 24) THEN FALSE
        ELSE NULL
    END AS has_blackout_curtain,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 25) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 25) THEN FALSE
        ELSE NULL
    END AS has_decorative_curtain,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 26) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 26) THEN FALSE
        ELSE NULL
    END AS has_soundproof_window,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 27) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 27) THEN FALSE
        ELSE NULL
    END AS has_ceiling_fan,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 28) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 28) THEN FALSE
        ELSE NULL
    END AS has_natural_light,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 29) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 29) THEN FALSE
        ELSE NULL
    END AS has_free_view,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 30) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 30) THEN FALSE
        ELSE NULL
    END AS has_silent_street,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 31) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 31) THEN FALSE
        ELSE NULL
    END AS has_eletric_shower,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 32) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 32) THEN FALSE
        ELSE NULL
    END AS has_microwave,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 33) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 33) THEN FALSE
        ELSE NULL
    END AS has_sofa,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 34) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 34) THEN FALSE
        ELSE NULL
    END AS has_washing_machine,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 35) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 35) THEN FALSE
        ELSE NULL
    END AS has_dryer_machine,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 36) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 36) THEN FALSE
        ELSE NULL
    END AS has_wash_dry_machine,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 37) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 37) THEN FALSE
        ELSE NULL
    END AS has_utility_sink,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 38) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 38) THEN FALSE
        ELSE NULL
    END AS has_protection_net,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 39) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 39) THEN FALSE
        ELSE NULL
    END AS has_clothesline,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 40) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 40) THEN FALSE
        ELSE NULL
    END AS has_new_outlet,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 41) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 41) THEN FALSE
        ELSE NULL
    END AS has_television,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 42) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 42) THEN FALSE
        ELSE NULL
    END AS has_table_and_chair,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 43) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 43) THEN FALSE
        ELSE NULL
    END AS has_coffee_machine,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 44) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 44) THEN FALSE
        ELSE NULL
    END AS has_grill,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 45) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 45) THEN FALSE
        ELSE NULL
    END AS has_step_free_access,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 46) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 46) THEN FALSE
        ELSE NULL
    END AS has_cooktop,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 47) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 47) THEN FALSE
        ELSE NULL
    END AS has_kitchen_utensils,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 48) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 48) THEN FALSE
        ELSE NULL
    END AS has_double_bed,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 49) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 49) THEN FALSE
        ELSE NULL
    END AS has_single_bed,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 50) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 50) THEN FALSE
        ELSE NULL
    END AS has_bathroom_mirror,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 51) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 51) THEN FALSE
        ELSE NULL
    END AS has_eletronic_lock,
    CASE
        WHEN ARRAY_CONTAINS(amenities_with, 52) THEN TRUE
        WHEN ARRAY_CONTAINS(amenities_without, 52) THEN FALSE
        ELSE NULL
    END AS has_energy,
    CASE
        WHEN ARRAY_CONTAINS(condo_amenities_with, 1) THEN TRUE
        WHEN ARRAY_CONTAINS(condo_amenities_without, 1) THEN FALSE
        ELSE NULL
    END AS has_playground,
    CASE
        WHEN ARRAY_CONTAINS(condo_amenities_with, 2) THEN TRUE
        WHEN ARRAY_CONTAINS(condo_amenities_without, 2) THEN FALSE
        ELSE NULL
    END AS has_condominium_swimming_pool,
    CASE
        WHEN ARRAY_CONTAINS(condo_amenities_with, 3) THEN TRUE
        WHEN ARRAY_CONTAINS(condo_amenities_without, 3) THEN FALSE
        ELSE NULL
    END AS has_condominium_grill,
    CASE
        WHEN ARRAY_CONTAINS(condo_amenities_with, 4) THEN TRUE
        WHEN ARRAY_CONTAINS(condo_amenities_without, 4) THEN FALSE
        ELSE NULL
    END AS has_sports_court,
    CASE
        WHEN ARRAY_CONTAINS(condo_amenities_with, 5) THEN TRUE
        WHEN ARRAY_CONTAINS(condo_amenities_without, 5) THEN FALSE
        ELSE NULL
    END AS has_gym,
    CASE
        WHEN ARRAY_CONTAINS(condo_amenities_with, 6) THEN TRUE
        WHEN ARRAY_CONTAINS(condo_amenities_without, 6) THEN FALSE
        ELSE NULL
    END AS has_party_room,
    CASE
        WHEN ARRAY_CONTAINS(condo_amenities_with, 7) THEN TRUE
        WHEN ARRAY_CONTAINS(condo_amenities_without, 7) THEN FALSE
        ELSE NULL
    END AS has_sauna,
    CASE
        WHEN ARRAY_CONTAINS(condo_amenities_with, 8) THEN TRUE
        WHEN ARRAY_CONTAINS(condo_amenities_without, 8) THEN FALSE
        ELSE NULL
    END AS has_laundry,
    CASE
        WHEN ARRAY_CONTAINS(condo_amenities_with, 9) THEN TRUE
        WHEN ARRAY_CONTAINS(condo_amenities_without, 9) THEN FALSE
        ELSE NULL
    END AS has_piped_gas,
    CASE
        WHEN ARRAY_CONTAINS(condo_amenities_with, 10) THEN TRUE
        WHEN ARRAY_CONTAINS(condo_amenities_without, 10) THEN FALSE
        ELSE NULL
    END AS has_automatic_gate,
    CASE
        WHEN ARRAY_CONTAINS(condo_amenities_with, 11) THEN TRUE
        WHEN ARRAY_CONTAINS(condo_amenities_without, 11) THEN FALSE
        ELSE NULL
    END AS has_gourmet_space,
    CASE
        WHEN ARRAY_CONTAINS(condo_amenities_with, 12) THEN TRUE
        WHEN ARRAY_CONTAINS(condo_amenities_without, 12) THEN FALSE
        ELSE NULL
    END AS is_subway_close,
    NOW() AS ts_load
FROM
    amenities AS a
FULL JOIN
    condo_amenities AS ca
        ON a.id_house = ca.id_house
FULL JOIN
    datalake_ebdb_clean.house_maintenance_condition AS hmc
        ON COALESCE(a.id_house, ca.id_house) = hmc.id_house
