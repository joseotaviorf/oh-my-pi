WITH base AS (
    SELECT
        m.id AS id_message,
        m.id_session,
        s.id AS id_state,
        m.message_index,
        m.role,
        m.input_type,
        m.content,
        s.flow,
        from_json(
            state, 
            "
            STRUCT<
                searchEnabled: BOOLEAN,
                count: INTEGER,
                location: STRING,
                askedForFilters: BOOLEAN,
                filters: STRUCT<
                    acceptPets: STRING,
                    amenities: ARRAY<STRING>,
                    area: STRUCT<
                        max: FLOAT,
                        min: FLOAT
                    >,
                    availability: STRING,
                    bathrooms: STRUCT<
                        max: INTEGER,
                        min: INTEGER
                    >,
                    bedrooms: STRUCT<
                        max: INTEGER,
                        min: INTEGER
                    >,
                    businessContext: STRING,
                    floor: INTEGER,
                    installations: ARRAY<STRING>,
                    isFurnished: BOOLEAN,
                    location: STRING,
                    nearSubway: BOOLEAN,
                    parkingSpace: STRUCT<
                        max: INTEGER,
                        min: INTEGER
                    >,
                    price: STRUCT<
                        max: DOUBLE,
                        min: DOUBLE,
                        priceType: STRING
                    >,
                    propertyType: ARRAY<STRING>,
                    suites: STRUCT<
                        max: INTEGER,
                        min: INTEGER
                    >,
                    visualAspects: ARRAY<STRING>
                >
            >
            "
        ) AS state,
        m.ts_created AS ts_message_sent
    FROM
        datalake_copilot_service_clean.message AS m
    LEFT JOIN
        datalake_copilot_service_clean.state AS s
        ON m.id = s.id_message
)

SELECT 
    id_message,
    id_session,
    id_state,
    message_index,
    role,
    input_type,
    content,
    flow,
    role NOT IN ("HARDCODED", "SUMMARY") AND flow = "SEARCH" AND message_index = MAX(message_index) OVER(PARTITION BY id_session) AS is_last_search_message,
    state.searchEnabled AS is_search_qualified,
    state.searchEnabled IS TRUE AND LAG(state.searchEnabled, 1) OVER(PARTITION BY id_session ORDER BY message_index) IS FALSE AS is_the_search_qualification_event,
    state.count AS search_count,
    state.location AS geocoded_location,
    state.askedForFilters AS asked_for_filters,
    state.filters.acceptPets AS accept_pets,
    state.filters.amenities,
    state.filters.area.min AS min_area,
    state.filters.area.max AS max_area,
    state.filters.availability,
    state.filters.bathrooms.min AS min_bathrooms,
    state.filters.bathrooms.max AS max_bathrooms,
    state.filters.bedrooms.min AS min_bedrooms,
    state.filters.bedrooms.max AS max_bedrooms,
    state.filters.businessContext AS business_context,
    state.filters.floor,
    state.filters.installations,
    state.filters.isFurnished AS is_furnished,
    state.filters.location,
    state.filters.nearSubway AS near_subway,
    state.filters.parkingSpace.min AS min_parking_spaces,
    state.filters.parkingSpace.max AS max_parking_spaces,
    state.filters.price.min AS min_price,
    state.filters.price.max AS max_price,
    state.filters.price.priceType AS price_type,
    state.filters.propertyType AS property_type,
    state.filters.suites.min AS min_suites,
    state.filters.suites.max AS max_suites,
    state.filters.visualAspects AS visual_aspects,
    CONCAT(state.filters.amenities, state.filters.installations) AS amenities_installations
FROM base