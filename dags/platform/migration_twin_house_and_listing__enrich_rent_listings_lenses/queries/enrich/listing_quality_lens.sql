WITH amenities_history AS (
  SELECT
    id_house,
    IF(h.is_condo_amenity, CONCAT(code, "_CONDO"), code) AS code,
    COALESCE(UPPER(has_feature::STRING), "NULL") AS has_feature,
    ts_change
  FROM
    datalake_ebdb_amenities.amenity_change_history AS h
  LEFT JOIN
    datalake_ebdb_amenities.amenity AS a
      USING(id_amenity, is_condo_amenity)
),
amenities AS (
  SELECT
      id_house,
      code,
      has_feature,
      DATE(ts_change) AS dt_change
  FROM
      amenities_history
  QUALIFY
      ROW_NUMBER() OVER (PARTITION BY id_house, code, DATE(ts_change) ORDER BY ts_change DESC) = 1
),
amenities_pivoted AS (
    SELECT
        id_house,
        dt_change,
        is_penthouse,
        is_pet_friendly,
        has_kitchen_cupboard,
        has_bathroom_cabinet,
        has_air_conditioning,
        has_gas_shower,
        has_natural_light,
        has_condo_pool,
        has_private_pool,
        has_balcony,
        has_ceiling_fan,
        has_condo_gym,
        has_condo_toy_library,
        has_condo_grill,
        has_condo_playground,
        has_condo_sports_court,
        has_condo_party_hall,
        has_condo_sauna
    FROM
        amenities
    PIVOT (
        MAX(has_feature)
    FOR
        code
    IN (
      "ACADEMIA_CONDO" AS has_condo_gym,
      "APARTAMENTO_COBERTURA" AS is_penthouse,
      "ARMARIOS_NA_COZINHA" AS has_kitchen_cupboard,
      "ARMARIOS_NOS_BANHEIROS" AS has_bathroom_cabinet,
      "AR_CONDICIONADO" AS has_air_conditioning,
      "BRINQUEDOTECA_CONDO" AS has_condo_toy_library,
      "CHURRASQUEIRA_CONDO" AS has_condo_grill,
      "CHUVEIRO_A_GAS" AS has_gas_shower,
      "LUMINOSIDADE_NATURAL" AS has_natural_light,
      "PISCINA_CONDO" AS has_condo_pool,
      "PISCINA_PRIVATIVA" AS has_private_pool,
      "PLAYGROUND_CONDO" AS has_condo_playground,
      "PODE_TER_ANIMAIS_DE_ESTIMACAO" AS is_pet_friendly,
      "QUADRA_ESPORTIVA_CONDO" AS has_condo_sports_court,
      "SALAO_DE_FESTAS_CONDO" AS has_condo_party_hall,
      "SAUNA_CONDO" AS has_condo_sauna,
      "VARANDA" AS has_balcony,
      "VENTILADOR_DE_TETO" AS has_ceiling_fan
    )
  )
),
house_aud AS (
    SELECT
        h_aud.id_house,
        h_aud.rent AS price,
        h_aud.bedrooms,
        h_aud.bathrooms,
        h_aud.total_area,
        h_aud.floor,
        h_aud.condo,
        h_aud.iptu,
        h_aud.parking_slots,
        h_aud.type,
        h_aud.doorman_type,
        h_aud.iptu_type,
        h_aud.has_elevator,
        h_aud.is_furnished,
        CASE
            WHEN lbc.ts_first_publication >= r.ts_revision THEN 'UNPUBLISHED'
            ELSE 'PUBLISHED'
        END AS status_threshold,
        ROW_NUMBER() OVER (PARTITION BY h_aud.id_house, IF(lbc.ts_first_publication >= r.ts_revision, 'UNPUBLISHED', 'PUBLISHED') ORDER BY h_aud.rev DESC) AS threshold,
        LAG(h_aud.rent) OVER (PARTITION BY h_aud.id_house ORDER BY r.ts_revision, h_aud.rev) IS DISTINCT FROM h_aud.rent AS has_price_changed,
        LAG(h_aud.bedrooms) OVER (PARTITION BY h_aud.id_house ORDER BY r.ts_revision, h_aud.rev) IS DISTINCT FROM h_aud.bedrooms AS has_bedrooms_changed,
        LAG(h_aud.bathrooms) OVER (PARTITION BY h_aud.id_house ORDER BY r.ts_revision, h_aud.rev) IS DISTINCT FROM h_aud.bathrooms AS has_bathrooms_changed,
        LAG(h_aud.total_area) OVER (PARTITION BY h_aud.id_house ORDER BY r.ts_revision, h_aud.rev) IS DISTINCT FROM h_aud.total_area AS has_total_area_changed,
        LAG(h_aud.floor) OVER (PARTITION BY h_aud.id_house ORDER BY r.ts_revision, h_aud.rev) IS DISTINCT FROM h_aud.floor AS has_floor_changed,
        LAG(h_aud.condo) OVER (PARTITION BY h_aud.id_house ORDER BY r.ts_revision, h_aud.rev) IS DISTINCT FROM h_aud.condo AS has_condo_changed,
        LAG(h_aud.iptu) OVER (PARTITION BY h_aud.id_house ORDER BY r.ts_revision, h_aud.rev) IS DISTINCT FROM h_aud.iptu AS has_iptu_changed,
        LAG(h_aud.parking_slots) OVER (PARTITION BY h_aud.id_house ORDER BY r.ts_revision, h_aud.rev) IS DISTINCT FROM h_aud.parking_slots AS has_parking_slots_changed,
        LAG(h_aud.type) OVER (PARTITION BY h_aud.id_house ORDER BY r.ts_revision, h_aud.rev) IS DISTINCT FROM h_aud.type AS has_type_changed,
        LAG(h_aud.doorman_type) OVER (PARTITION BY h_aud.id_house ORDER BY r.ts_revision, h_aud.rev) IS DISTINCT FROM h_aud.doorman_type AS has_doorman_type_changed,
        LAG(h_aud.iptu_type) OVER (PARTITION BY h_aud.id_house ORDER BY r.ts_revision, h_aud.rev) IS DISTINCT FROM h_aud.iptu_type AS has_iptu_type_changed,
        LAG(h_aud.has_elevator) OVER (PARTITION BY h_aud.id_house ORDER BY r.ts_revision, h_aud.rev) IS DISTINCT FROM h_aud.has_elevator AS has_elevator_changed,
        LAG(h_aud.is_furnished) OVER (PARTITION BY h_aud.id_house ORDER BY r.ts_revision, h_aud.rev) IS DISTINCT FROM h_aud.is_furnished AS is_furnished_changed,
        DATE(r.ts_revision) AS dt_change,
        r.ts_revision
    FROM
        datalake_ebdb_clean.house_aud AS h_aud
    INNER JOIN
        datalake_ebdb_user.user_revision_entity AS r
            ON h_aud.rev = r.id
    INNER JOIN
        datalake_ebdb_clean.listing_business_context AS lbc
            ON lbc.id_house = h_aud.id_house
    WHERE
        lbc.business_context = 'RENT'
),
house_changes AS (
    SELECT
        id_house,
        price,
        bedrooms,
        bathrooms,
        total_area,
        floor,
        condo,
        iptu,
        parking_slots,
        type,
        doorman_type,
        iptu_type,
        has_elevator,
        is_furnished,
        dt_change
    FROM
        house_aud
    WHERE
        ((status_threshold = 'UNPUBLISHED' AND threshold = 1)
          OR (status_threshold = 'PUBLISHED'
              AND (has_price_changed = TRUE
                   OR has_bedrooms_changed = TRUE
                   OR has_bathrooms_changed = TRUE
                   OR has_total_area_changed = TRUE
                   OR has_floor_changed = TRUE
                   OR has_condo_changed = TRUE
                   OR has_iptu_changed = TRUE
                   OR has_parking_slots_changed = TRUE
                   OR has_type_changed = TRUE
                   OR has_doorman_type_changed = TRUE
                   OR has_iptu_type_changed = TRUE
                   OR has_elevator_changed = TRUE
                   OR is_furnished_changed = TRUE)))
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_house, dt_change ORDER BY ts_revision DESC) = 1
),
key_location_changes AS (
    SELECT
        id_house,
        key_location AS key_location_type,
        DATE(ts_entrance_started) AS dt_change
    FROM
        datalake_ebdb_listing.house_entrance_history
    WHERE
        is_last_status_of_day
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_house, DATE(ts_entrance_started) ORDER BY ts_entrance_started DESC) = 1
),
all_information AS (
    SELECT
        id_house,
        dt_change,
        price,
        bedrooms,
        bathrooms,
        total_area,
        floor,
        condo,
        NULL AS house_condition,
        iptu,
        parking_slots,
        type,
        doorman_type,
        iptu_type,
        NULL AS key_location_type,
        NULL AS is_listing_accurate,
        NULL AS is_penthouse,
        NULL AS is_pet_friendly,
        is_furnished,
        has_elevator,
        NULL AS has_condo_gym,
        NULL AS has_kitchen_cupboard,
        NULL AS has_bathroom_cabinet,
        NULL AS has_air_conditioning,
        NULL AS has_condo_toy_library,
        NULL AS has_condo_grill,
        NULL AS has_gas_shower,
        NULL AS has_natural_light,
        NULL AS has_condo_pool,
        NULL AS has_private_pool,
        NULL AS has_condo_playground,
        NULL AS has_condo_sports_court,
        NULL AS has_condo_party_hall,
        NULL AS has_condo_sauna,
        NULL AS has_balcony,
        NULL AS has_ceiling_fan
    FROM
        house_changes
    UNION ALL
    SELECT
        id_house,
        dt_change,
        NULL AS price,
        NULL AS bedrooms,
        NULL AS bathrooms,
        NULL AS total_area,
        NULL AS floor,
        NULL AS house_condition,
        NULL AS condo,
        NULL AS iptu,
        NULL AS parking_slots,
        NULL AS type,
        NULL AS doorman_type,
        NULL AS iptu_type,
        key_location_type,
        NULL AS is_listing_accurate,
        NULL AS is_penthouse,
        NULL AS is_pet_friendly,
        NULL AS is_furnished,
        NULL AS has_elevator,
        NULL AS has_condo_gym,
        NULL AS has_kitchen_cupboard,
        NULL AS has_bathroom_cabinet,
        NULL AS has_air_conditioning,
        NULL AS has_condo_toy_library,
        NULL AS has_condo_grill,
        NULL AS has_gas_shower,
        NULL AS has_natural_light,
        NULL AS has_condo_pool,
        NULL AS has_private_pool,
        NULL AS has_condo_playground,
        NULL AS has_condo_sports_court,
        NULL AS has_condo_party_hall,
        NULL AS has_condo_sauna,
        NULL AS has_balcony,
        NULL AS has_ceiling_fan
    FROM
        key_location_changes
    UNION ALL
    SELECT
        id_house,
        dt_condition_started AS dt_change,
        NULL AS price,
        NULL AS bedrooms,
        NULL AS bathrooms,
        NULL AS total_area,
        NULL AS floor,
        NULL AS condo,
        house_condition,
        NULL AS iptu,
        NULL AS parking_slots,
        NULL AS type,
        NULL AS doorman_type,
        NULL AS iptu_type,
        NULL AS key_location_type,
        NULL AS is_listing_accurate,
        NULL AS is_penthouse,
        NULL AS is_pet_friendly,
        NULL AS is_furnished,
        NULL AS has_elevator,
        NULL AS has_condo_gym,
        NULL AS has_kitchen_cupboard,
        NULL AS has_bathroom_cabinet,
        NULL AS has_air_conditioning,
        NULL AS has_condo_toy_library,
        NULL AS has_condo_grill,
        NULL AS has_gas_shower,
        NULL AS has_natural_light,
        NULL AS has_condo_pool,
        NULL AS has_private_pool,
        NULL AS has_condo_playground,
        NULL AS has_condo_sports_court,
        NULL AS has_condo_party_hall,
        NULL AS has_condo_sauna,
        NULL AS has_balcony,
        NULL AS has_ceiling_fan
    FROM
        datalake_ebdb_house.maintenance_condition_history
    UNION ALL
    SELECT
        id_house,
        dt_change,
        NULL AS price,
        NULL AS bedrooms,
        NULL AS bathrooms,
        NULL AS total_area,
        NULL AS floor,
        NULL AS house_condition,
        NULL AS condo,
        NULL AS iptu,
        NULL AS parking_slots,
        NULL AS type,
        NULL AS doorman_type,
        NULL AS iptu_type,
        NULL AS key_location_type,
        is_listing_accurate,
        NULL AS is_penthouse,
        NULL AS is_pet_friendly,
        NULL AS is_furnished,
        NULL AS has_elevator,
        NULL AS has_condo_gym,
        NULL AS has_kitchen_cupboard,
        NULL AS has_bathroom_cabinet,
        NULL AS has_air_conditioning,
        NULL AS has_condo_toy_library,
        NULL AS has_condo_grill,
        NULL AS has_gas_shower,
        NULL AS has_natural_light,
        NULL AS has_condo_pool,
        NULL AS has_private_pool,
        NULL AS has_condo_playground,
        NULL AS has_condo_sports_court,
        NULL AS has_condo_party_hall,
        NULL AS has_condo_sauna,
        NULL AS has_balcony,
        NULL AS has_ceiling_fan
    FROM
        datalake_listing_accuracy_review.listing_accuracy_history
    UNION ALL
    SELECT
        id_house,
        dt_change,
        NULL AS price,
        NULL AS bedrooms,
        NULL AS bathrooms,
        NULL AS total_area,
        NULL AS floor,
        NULL AS house_condition,
        NULL AS condo,
        NULL AS iptu,
        NULL AS parking_slots,
        NULL AS type,
        NULL AS doorman_type,
        NULL AS iptu_type,
        NULL AS key_location_type,
        NULL AS is_listing_accurate,
        is_penthouse,
        is_pet_friendly,
        NULL AS is_furnished,
        NULL AS has_elevator,
        has_condo_gym,
        has_kitchen_cupboard,
        has_bathroom_cabinet,
        has_air_conditioning,
        has_condo_toy_library,
        has_condo_grill,
        has_gas_shower,
        has_natural_light,
        has_condo_pool,
        has_private_pool,
        has_condo_playground,
        has_condo_sports_court,
        has_condo_party_hall,
        has_condo_sauna,
        has_balcony,
        has_ceiling_fan
    FROM
        amenities_pivoted
),
grouping_events_by_day AS (
    SELECT
        id_house,
        dt_change,
        MAX(price) AS price,
        MAX(bedrooms) AS bedrooms,
        MAX(bathrooms) AS bathrooms,
        MAX(total_area) AS total_area,
        MAX(floor) AS floor,
        MAX(condo) AS condo,
        MAX(house_condition) AS house_condition,
        MAX(iptu) AS iptu,
        MAX(parking_slots) AS parking_slots,
        MAX(type) AS type,
        MAX(doorman_type) AS doorman_type,
        MAX(iptu_type) AS iptu_type,
        MAX(key_location_type) AS key_location_type,
        MAX(is_listing_accurate) AS is_listing_accurate,
        MAX(is_penthouse) AS is_penthouse,
        MAX(is_pet_friendly) AS is_pet_friendly,
        MAX(is_furnished) AS is_furnished,
        MAX(has_elevator) AS has_elevator,
        MAX(has_condo_gym) AS has_condo_gym,
        MAX(has_kitchen_cupboard) AS has_kitchen_cupboard,
        MAX(has_bathroom_cabinet) AS has_bathroom_cabinet,
        MAX(has_air_conditioning) AS has_air_conditioning,
        MAX(has_condo_toy_library) AS has_condo_toy_library,
        MAX(has_condo_grill) AS has_condo_grill,
        MAX(has_gas_shower) AS has_gas_shower,
        MAX(has_natural_light) AS has_natural_light,
        MAX(has_condo_pool) AS has_condo_pool,
        MAX(has_private_pool) AS has_private_pool,
        MAX(has_condo_playground) AS has_condo_playground,
        MAX(has_condo_sports_court) AS has_condo_sports_court,
        MAX(has_condo_party_hall) AS has_condo_party_hall,
        MAX(has_condo_sauna) AS has_condo_sauna,
        MAX(has_balcony) AS has_balcony,
        MAX(has_ceiling_fan) AS has_ceiling_fan
    FROM
        all_information
    GROUP BY
        1, 2
),
dataset AS (
    SELECT
        id_house,
        LAST_VALUE(price, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS price,
        LAST_VALUE(bedrooms, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS bedrooms,
        LAST_VALUE(bathrooms, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS bathrooms,
        LAST_VALUE(total_area, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS total_area,
        LAST_VALUE(floor, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS floor,
        LAST_VALUE(condo, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS condo,
        LAST_VALUE(house_condition, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS house_condition,
        LAST_VALUE(iptu, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS iptu,
        LAST_VALUE(parking_slots, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS parking_slots,
        LAST_VALUE(type, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS type,
        LAST_VALUE(doorman_type, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS doorman_type,
        LAST_VALUE(iptu_type, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS iptu_type,
        LAST_VALUE(key_location_type, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS key_location_type,
        IF(
            DATEDIFF(dt_change, LAG(dt_change) OVER (PARTITION BY id_house ORDER BY dt_change)) <= 120,
            LAST_VALUE(is_listing_accurate, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change),
            NULL
        ) AS is_listing_accurate,
        LAST_VALUE(is_penthouse, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS is_penthouse,
        LAST_VALUE(is_pet_friendly, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS is_pet_friendly,
        LAST_VALUE(is_furnished, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS is_furnished,
        LAST_VALUE(has_elevator, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS has_elevator,
        LAST_VALUE(has_condo_gym, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS has_condo_gym,
        LAST_VALUE(has_kitchen_cupboard, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS has_kitchen_cupboard,
        LAST_VALUE(has_bathroom_cabinet, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS has_bathroom_cabinet,
        LAST_VALUE(has_air_conditioning, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS has_air_conditioning,
        LAST_VALUE(has_condo_toy_library, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS has_condo_toy_library,
        LAST_VALUE(has_condo_grill, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS has_condo_grill,
        LAST_VALUE(has_gas_shower, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS has_gas_shower,
        LAST_VALUE(has_natural_light, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS has_natural_light,
        LAST_VALUE(has_condo_pool, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS has_condo_pool,
        LAST_VALUE(has_private_pool, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS has_private_pool,
        LAST_VALUE(has_condo_playground, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS has_condo_playground,
        LAST_VALUE(has_condo_sports_court, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS has_condo_sports_court,
        LAST_VALUE(has_condo_party_hall, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS has_condo_party_hall,
        LAST_VALUE(has_condo_sauna, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS has_condo_sauna,
        LAST_VALUE(has_balcony, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS has_balcony,
        LAST_VALUE(has_ceiling_fan, TRUE) OVER (PARTITION BY id_house ORDER BY dt_change) AS has_ceiling_fan,
        dt_change AS date,
        DATE(ts_first_publication) AS dt_first_publication
    FROM
        grouping_events_by_day
    INNER JOIN
        datalake_ebdb_listing.rent_listing
            USING(id_house)
),
returning_booleans AS (
    SELECT
        id_house,
        price,
        bedrooms,
        bathrooms,
        total_area,
        floor,
        condo,
        IF(house_condition = 'NULL', NULL, house_condition) AS house_condition,
        iptu,
        parking_slots,
        type,
        doorman_type,
        iptu_type,
        IF(key_location_type = 'NULL', NULL, key_location_type) AS key_location_type,
        is_listing_accurate,
        is_furnished,
        CASE
            WHEN is_penthouse = 'TRUE' THEN TRUE
            WHEN is_penthouse = 'FALSE' THEN FALSE
            WHEN is_penthouse = 'NULL' THEN NULL
        END AS is_penthouse,
        CASE
            WHEN is_pet_friendly = 'TRUE' THEN TRUE
            WHEN is_pet_friendly = 'FALSE' THEN FALSE
            WHEN is_pet_friendly = 'NULL' THEN NULL
        END AS is_pet_friendly,
        CASE
            WHEN has_elevator = 'TRUE' THEN TRUE
            WHEN has_elevator = 'FALSE' THEN FALSE
            WHEN has_elevator = 'NULL' THEN NULL
        END AS has_elevator,
        CASE
            WHEN has_condo_gym = 'TRUE' THEN TRUE
            WHEN has_condo_gym = 'FALSE' THEN FALSE
            WHEN has_condo_gym = 'NULL' THEN NULL
        END AS has_condo_gym,
        CASE
            WHEN has_kitchen_cupboard = 'TRUE' THEN TRUE
            WHEN has_kitchen_cupboard = 'FALSE' THEN FALSE
            WHEN has_kitchen_cupboard = 'NULL' THEN NULL
        END AS has_kitchen_cupboard,
        CASE
            WHEN has_bathroom_cabinet = 'TRUE' THEN TRUE
            WHEN has_bathroom_cabinet = 'FALSE' THEN FALSE
            WHEN has_bathroom_cabinet = 'NULL' THEN NULL
        END AS has_bathroom_cabinet,
        CASE
            WHEN has_air_conditioning = 'TRUE' THEN TRUE
            WHEN has_air_conditioning = 'FALSE' THEN FALSE
            WHEN has_air_conditioning = 'NULL' THEN NULL
        END AS has_air_conditioning,
        CASE
            WHEN has_condo_toy_library = 'TRUE' THEN TRUE
            WHEN has_condo_toy_library = 'FALSE' THEN FALSE
            WHEN has_condo_toy_library = 'NULL' THEN NULL
        END AS has_condo_toy_library,
        CASE
            WHEN has_condo_grill = 'TRUE' THEN TRUE
            WHEN has_condo_grill = 'FALSE' THEN FALSE
            WHEN has_condo_grill = 'NULL' THEN NULL
        END AS has_condo_grill,
        CASE
            WHEN has_gas_shower = 'TRUE' THEN TRUE
            WHEN has_gas_shower = 'FALSE' THEN FALSE
            WHEN has_gas_shower = 'NULL' THEN NULL
        END AS has_gas_shower,
        CASE
            WHEN has_natural_light = 'TRUE' THEN TRUE
            WHEN has_natural_light = 'FALSE' THEN FALSE
            WHEN has_natural_light = 'NULL' THEN NULL
        END AS has_natural_light,
        CASE
            WHEN has_condo_pool = 'TRUE' THEN TRUE
            WHEN has_condo_pool = 'FALSE' THEN FALSE
            WHEN has_condo_pool = 'NULL' THEN NULL
        END AS has_condo_pool,
        CASE
            WHEN has_private_pool = 'TRUE' THEN TRUE
            WHEN has_private_pool = 'FALSE' THEN FALSE
            WHEN has_private_pool = 'NULL' THEN NULL
        END AS has_private_pool,
        CASE
            WHEN has_condo_playground = 'TRUE' THEN TRUE
            WHEN has_condo_playground = 'FALSE' THEN FALSE
            WHEN has_condo_playground = 'NULL' THEN NULL
        END AS has_condo_playground,
        CASE
            WHEN has_condo_sports_court = 'TRUE' THEN TRUE
            WHEN has_condo_sports_court = 'FALSE' THEN FALSE
            WHEN has_condo_sports_court = 'NULL' THEN NULL
        END AS has_condo_sports_court,
        CASE
            WHEN has_condo_party_hall = 'TRUE' THEN TRUE
            WHEN has_condo_party_hall = 'FALSE' THEN FALSE
            WHEN has_condo_party_hall = 'NULL' THEN NULL
        END AS has_condo_party_hall,
        CASE
            WHEN has_condo_sauna = 'TRUE' THEN TRUE
            WHEN has_condo_sauna = 'FALSE' THEN FALSE
            WHEN has_condo_sauna = 'NULL' THEN NULL
        END AS has_condo_sauna,
        CASE
            WHEN has_balcony = 'TRUE' THEN TRUE
            WHEN has_balcony = 'FALSE' THEN FALSE
            WHEN has_balcony = 'NULL' THEN NULL
        END AS has_balcony,
        CASE
            WHEN has_ceiling_fan = 'TRUE' THEN TRUE
            WHEN has_ceiling_fan = 'FALSE' THEN FALSE
            WHEN has_ceiling_fan = 'NULL' THEN NULL
        END AS has_ceiling_fan,
        date
    FROM
        dataset
    QUALIFY
        COUNT(*) OVER (PARTITION BY id_house) = 1 OR date >= dt_first_publication
),
business_logic AS (
    SELECT
        id_house,
        IF(price < 500 OR price > 70000 OR price IS NULL, -10000, 0) AS price_score,
        IF(bedrooms = 0 OR bedrooms IS NULL, -10000, 0) AS bedrooms_score,
        IF(bathrooms = 0 OR bathrooms IS NULL, -10000, 0) AS bathrooms_score,
        IF(total_area < 5 OR total_area > 1000 OR total_area IS NULL, -10000, 0) AS total_area_score,
        IF(floor IS NULL AND type IN ('Apartamento','StudioOuKitchenette'), -100, 0) AS floor_score,
        IF(condo < 10 AND type IN ('Apartamento','CasaCondominio','StudioOuKitchenette'), -10000, 0) AS condo_score,
        IF(house_condition IS NULL, -200, 0) AS house_condition_score,
        IF(iptu IS NULL OR (iptu <= 0 AND iptu_type IN ('NaoInformado','Normal')), -50, 0) AS iptu_score,
        IF(parking_slots IS NULL, -400, 0) AS parking_slots_score,
        IF(type IS NULL, -300, 0) AS type_score,
        IF(doorman_type IS NULL AND type IN ('Apartamento', 'CasaCondominio', 'StudioOuKitchenette'), -200, 0) AS doorman_type_score,
        IF(key_location_type IS NULL OR key_location_type = 'NONE', -400, 0) AS key_location_score,
        IF(is_listing_accurate IS FALSE, -10000, 0) AS listing_accuracy_score,
        IF(is_furnished IS FALSE, -100, 0) AS furniture_score,
        IF(is_penthouse IS NULL, -50, 0) AS penthouse_score,
        IF(is_pet_friendly IS NULL, -100, 0) AS pet_friendly_score,
        IF(has_elevator IS NULL AND type IN ('Apartamento', 'CasaCondominio', 'StudioOuKitchenette'), -300, 0) AS elevator_score,
        IF(has_condo_gym IS NULL AND type IN ('Apartamento', 'CasaCondominio', 'StudioOuKitchenette'), -300, 0) AS gym_score,
        IF(has_kitchen_cupboard IS NULL, -50, 0) AS kitchen_cupboard_score,
        IF(has_bathroom_cabinet IS NULL, -50, 0) AS bathroom_cabinet_score,
        IF(has_air_conditioning IS NULL, -50, 0) AS air_conditioning_score,
        IF(has_condo_toy_library IS NULL AND type IN ('Apartamento', 'CasaCondominio', 'StudioOuKitchenette'), -100, 0) AS toy_library_score,
        IF(has_condo_grill IS NULL AND type IN ('Apartamento', 'CasaCondominio', 'StudioOuKitchenette'), -200, 0) AS grill_score,
        IF(has_gas_shower IS NULL, -50, 0) AS gas_shower_score,
        IF(has_natural_light IS NULL, -50, 0) AS natural_light_score,
        IF(has_condo_pool IS NULL AND type IN ('Apartamento', 'CasaCondominio', 'StudioOuKitchenette'), -300, 0) AS pool_score,
        IF(has_private_pool IS NULL AND type NOT IN ('Apartamento', 'CasaCondominio', 'StudioOuKitchenette'), -100, 0) AS private_pool_score,
        IF(has_condo_playground IS NULL AND type IN ('Apartamento', 'CasaCondominio', 'StudioOuKitchenette'), -200, 0) AS playground_score,
        IF(has_condo_sports_court IS NULL AND type IN ('Apartamento', 'CasaCondominio', 'StudioOuKitchenette'), -200, 0) AS sports_court_score,
        IF(has_condo_party_hall IS NULL AND type IN ('Apartamento', 'CasaCondominio', 'StudioOuKitchenette'), -200, 0) AS party_hall_score,
        IF(has_condo_sauna IS NULL AND type IN ('Apartamento', 'CasaCondominio', 'StudioOuKitchenette'), -200, 0) AS sauna_score,
        IF(has_balcony IS NULL, -200, 0) AS balcony_score,
        IF(has_ceiling_fan IS NULL, -50, 0) AS ceiling_fan_score,
        date
    FROM
        returning_booleans
),
score AS (
    SELECT
        id_house,
        price_score,
        bedrooms_score,
        bathrooms_score,
        total_area_score,
        floor_score,
        condo_score,
        house_condition_score,
        iptu_score,
        parking_slots_score,
        type_score,
        doorman_type_score,
        key_location_score,
        listing_accuracy_score,
        furniture_score,
        penthouse_score,
        pet_friendly_score,
        elevator_score,
        gym_score,
        kitchen_cupboard_score,
        bathroom_cabinet_score,
        air_conditioning_score,
        toy_library_score,
        grill_score,
        gas_shower_score,
        natural_light_score,
        pool_score,
        private_pool_score,
        playground_score,
        sports_court_score,
        party_hall_score,
        sauna_score,
        balcony_score,
        ceiling_fan_score,
        ARRAY(
            price_score,
            bedrooms_score,
            bathrooms_score,
            total_area_score,
            floor_score,
            condo_score,
            house_condition_score,
            iptu_score,
            parking_slots_score,
            type_score,
            doorman_type_score,
            key_location_score,
            listing_accuracy_score,
            furniture_score,
            penthouse_score,
            pet_friendly_score,
            elevator_score,
            gym_score,
            kitchen_cupboard_score,
            bathroom_cabinet_score,
            air_conditioning_score,
            toy_library_score,
            grill_score,
            gas_shower_score,
            natural_light_score,
            pool_score,
            private_pool_score,
            playground_score,
            sports_court_score,
            party_hall_score,
            sauna_score,
            balcony_score,
            ceiling_fan_score
        ) AS score_components,
        date
  FROM
    business_logic
),
create_completeness AS (
  SELECT
    id_house,
    price_score,
    bedrooms_score,
    bathrooms_score,
    total_area_score,
    floor_score,
    condo_score,
    house_condition_score,
    iptu_score,
    parking_slots_score,
    type_score,
    doorman_type_score,
    key_location_score,
    listing_accuracy_score,
    furniture_score,
    penthouse_score,
    pet_friendly_score,
    elevator_score,
    gym_score,
    kitchen_cupboard_score,
    bathroom_cabinet_score,
    air_conditioning_score,
    toy_library_score,
    grill_score,
    gas_shower_score,
    natural_light_score,
    pool_score,
    private_pool_score,
    playground_score,
    sports_court_score,
    party_hall_score,
    sauna_score,
    balcony_score,
    ceiling_fan_score,
    AGGREGATE(score_components, 0, (acc, x) -> acc + x) AS listing_quality_score,
    score_components,
    SIZE(FILTER(score_components, x -> x == 0))/SIZE(score_components) AS component_completeness,
    date
  FROM
    score
),
create_tiers AS (
    SELECT
        id_house,
        CASE
            WHEN price_score < 0 THEN 'Q1'
            WHEN bedrooms_score < 0 THEN 'Q1'
            WHEN total_area_score < 0 THEN 'Q1'
            WHEN condo_score < 0 THEN 'Q1'
            WHEN listing_quality_score = 0 THEN 'Q5'
            WHEN listing_quality_score BETWEEN -500 AND -0 THEN 'Q4'
            WHEN listing_quality_score BETWEEN -1500 AND -500 THEN 'Q3'
            WHEN listing_quality_score < -1500 THEN 'Q2'
        END AS tier,
        CASE
            WHEN listing_quality_score = 0 THEN 'Everything looks Great. '
            WHEN condo_score < 0 OR total_area_score < 0 OR price_score < 0 OR bedrooms_score < 0 THEN 'Critical information is incorrect'
            WHEN component_completeness <= 0.80 THEN  'Could be better. Needs increase amenities information'
            WHEN component_completeness > 0.8 THEN 'Good completeness of information'
        END AS tier_disclaimer,
        CASE
            WHEN listing_quality_score = 0 THEN 'Everything looks Great. 100% of amenities are enriched and no critical information was identified as incorrect.'
            WHEN condo_score < 0 OR total_area_score < 0 OR price_score < 0 OR bedrooms_score < 0
                THEN 'Critical information is incorrect: (' || IF(condo_score != 0, ' condo price,', '') || ''
                                                            || IF(total_area_score != 0, ' total area, ', '') || ''
                                                            || IF(price_score != 0, ' sale price,', '') || ''
                                                            || IF(bedrooms_score != 0, ' number of bedroom,', '')
                                                            || '). The percentage of amenities enriched is '
                                                            || CAST(ROUND(component_completeness * 100.0, 2) AS STRING) || '%'
            WHEN component_completeness <= 0.80 THEN 'The property has good completeness of information. Currently, ' || CAST(ROUND(component_completeness * 100.0, 2) AS STRING) || '%  of its amenities are enriched and no critical information was identified as incorrect.'
            WHEN component_completeness > 0.8 THEN 'The property could have more amenities enriched. Currently, ' || CAST(ROUND(component_completeness * 100.0, 2) AS STRING) || '% of its amenities are enriched and no critical information was identified as incorrect.'
        END AS tier_drill_down,
        listing_quality_score,
        component_completeness,
        price_score,
        bedrooms_score,
        bathrooms_score,
        total_area_score,
        floor_score,
        condo_score,
        house_condition_score,
        iptu_score,
        parking_slots_score,
        type_score,
        doorman_type_score,
        key_location_score,
        listing_accuracy_score,
        furniture_score,
        penthouse_score,
        pet_friendly_score,
        elevator_score,
        gym_score,
        kitchen_cupboard_score,
        bathroom_cabinet_score,
        air_conditioning_score,
        toy_library_score,
        grill_score,
        gas_shower_score,
        natural_light_score,
        pool_score,
        private_pool_score,
        playground_score,
        sports_court_score,
        party_hall_score,
        sauna_score,
        balcony_score,
        ceiling_fan_score,
        date AS ts_tier_started
    FROM
        create_completeness
),
grouping_tiers AS (
    SELECT
        id_house,
        tier,
        tier_disclaimer,
        tier_drill_down,
        listing_quality_score,
        component_completeness,
        price_score,
        bedrooms_score,
        bathrooms_score,
        total_area_score,
        floor_score,
        condo_score,
        house_condition_score,
        iptu_score,
        parking_slots_score,
        type_score,
        doorman_type_score,
        key_location_score,
        listing_accuracy_score,
        furniture_score,
        penthouse_score,
        pet_friendly_score,
        elevator_score,
        gym_score,
        kitchen_cupboard_score,
        bathroom_cabinet_score,
        air_conditioning_score,
        toy_library_score,
        grill_score,
        gas_shower_score,
        natural_light_score,
        pool_score,
        private_pool_score,
        playground_score,
        sports_court_score,
        party_hall_score,
        sauna_score,
        balcony_score,
        ceiling_fan_score,
        ts_tier_started
    FROM
        create_tiers
    QUALIFY
        tier IS DISTINCT FROM LAG(tier) OVER (PARTITION BY id_house ORDER BY ts_tier_started)
),
rent_version_order AS (
   SELECT
      id_house,
      id_house_listing,
      id_region,
      status_history,
      DATE(ts_status_started) AS dt_change
   FROM
      datalake_ebdb_listing.house_listing_status
   WHERE
      is_last_status_of_day
),
rent_status_version_order AS (
   SELECT
      id_house,
      id_house_listing,
      id_region,
      status_history,
      dt_change AS dt_status_started_date,
      DATE(DATEADD(DAY, -1, COALESCE(LEAD(dt_change) OVER (PARTITION BY id_house ORDER BY dt_change), CURRENT_DATE))) AS dt_status_ended_date
   FROM
      rent_version_order
),
tier_status AS (
    SELECT
        t.id_house,
        s.id_house_listing,
        s.id_region,
        COALESCE(s.status_history, 'PUBLISHED') AS status_history,
        t.tier,
        CASE
            WHEN t.tier = 'Q5' THEN 'Great Accuracy'
            WHEN t.tier = 'Q4' THEN 'Good Accuracy'
            WHEN t.tier = 'Q3' THEN 'Moderate Accuracy'
            WHEN t.tier = 'Q2' THEN 'Low Accuracy'
            WHEN t.tier = 'Q1' THEN 'Critical Accuracy'
        END AS tier_name,
        t.tier_disclaimer,
        t.tier_drill_down,
        t.listing_quality_score,
        t.component_completeness,
        t.price_score,
        t.bedrooms_score,
        t.bathrooms_score,
        t.total_area_score,
        t.floor_score,
        t.condo_score,
        t.house_condition_score,
        t.iptu_score,
        t.parking_slots_score,
        t.type_score,
        t.doorman_type_score,
        t.key_location_score,
        t.listing_accuracy_score,
        t.furniture_score,
        t.penthouse_score,
        t.pet_friendly_score,
        t.elevator_score,
        t.gym_score,
        t.kitchen_cupboard_score,
        t.bathroom_cabinet_score,
        t.air_conditioning_score,
        t.toy_library_score,
        t.grill_score,
        t.gas_shower_score,
        t.natural_light_score,
        t.pool_score,
        t.private_pool_score,
        t.playground_score,
        t.sports_court_score,
        t.party_hall_score,
        t.sauna_score,
        t.balcony_score,
        t.ceiling_fan_score,
        t.ts_tier_started,
        LEAD(t.ts_tier_started) OVER (PARTITION BY t.id_house ORDER BY t.ts_tier_started) AS ts_tier_ended
    FROM
        grouping_tiers AS t
    LEFT JOIN
      rent_status_version_order AS s
        ON s.id_house = t.id_house
        AND DATE_FORMAT(t.ts_tier_started , 'yyyy-MM-dd') BETWEEN s.dt_status_started_date AND COALESCE(s.dt_status_ended_date, CURRENT_TIMESTAMP)
)
SELECT
    id_house,
    id_house_listing,
    id_region,
    status_history,
    tier,
    tier_name,
    tier_disclaimer,
    tier_drill_down,
    listing_quality_score,
    component_completeness,
    price_score,
    bedrooms_score,
    bathrooms_score,
    total_area_score,
    floor_score,
    condo_score,
    house_condition_score,
    iptu_score,
    parking_slots_score,
    type_score,
    doorman_type_score,
    key_location_score,
    listing_accuracy_score,
    furniture_score,
    penthouse_score,
    pet_friendly_score,
    elevator_score,
    gym_score,
    kitchen_cupboard_score,
    bathroom_cabinet_score,
    air_conditioning_score,
    toy_library_score,
    grill_score,
    gas_shower_score,
    natural_light_score,
    pool_score,
    private_pool_score,
    playground_score,
    sports_court_score,
    party_hall_score,
    sauna_score,
    balcony_score,
    ceiling_fan_score,
    ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY ts_tier_started DESC) = 1 AS is_last_tier,
    ts_tier_started,
    DATE_SUB(ts_tier_ended, 1) AS ts_tier_ended
FROM
    tier_status
