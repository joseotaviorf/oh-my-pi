WITH base AS (
    SELECT
        m.id AS id_message,
        m.id_session,
        state.id AS id_state,
        session.id_user,
        CASE
          WHEN user.email LIKE "%@quintoandar.com.br"
          OR user.email IN (
            "edivaldo.delgado@poli.ufrj.br",
            "vicentedepaula@gmaill.com",
            "vpbfmail@gmail.com",
            "rafael.castro@gmail.com"
          ) THEN TRUE
          ELSE FALSE
        END AS is_internal_user,
        m.message_index,
        m.role,
        m.input_type,
        m.content,
        COALESCE(state.flow, flow.flow) AS flow,
        from_json(
            state, 
            "
            STRUCT<
                searchEnabled: BOOLEAN,
                count: INTEGER,
                location: STRING,
                askedForFilters: BOOLEAN,
                filters: STRUCT<
                    acceptPets: BOOLEAN,
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
                    locations: ARRAY<STRING>,
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
                    visualAspects: ARRAY<STRING>,
                    unsupportedFilters: ARRAY<STRING>
                >
            >
            "
        ) AS state,
        m.ts_created AS ts_message_sent,
        session.ts_created AS ts_session_created
    FROM
        datalake_copilot_service_clean.message AS m
    LEFT JOIN
        datalake_copilot_service_clean.message_flow AS flow
        ON m.id = flow.message_id
    LEFT JOIN
        datalake_copilot_service_clean.state
        ON m.id = state.id_message
    LEFT JOIN
        datalake_copilot_service_clean.session
        ON m.id_session = session.id
    LEFT JOIN
        datalake_ebdb_clean.user AS user
        ON session.id_user = user.id
    WHERE session.id_user NOT IN (
        "0", "1335847", "977002", "1234", "testUser"
    )
),

/*
  This CTE is responsible for shifting the state of the human messages
  to be that of the following message. This makes downstream processes
  that rely on computing previous vs. current state easier to implement.
*/
processed AS (
    SELECT
        *,
        CASE
          WHEN role = "HUMAN"
          THEN LEAD(state, 1) OVER(PARTITION BY id_session ORDER BY message_index)
          ELSE state
        END AS human_shifted_state
    FROM base
)

SELECT 
    id_message,
    id_session,
    id_state,
    id_user,
    message_index,
    role,
    input_type,
    content,
    flow,
    is_internal_user,
    FIRST(role) OVER(PARTITION BY id_session ORDER BY message_index) = "GREETING" AS is_non_cockpit_session,
    role NOT IN ("HARDCODED", "SUMMARY") AND flow = "SEARCH" AND message_index = MAX(message_index) OVER(PARTITION BY id_session) AS is_last_search_message,
    human_shifted_state.searchEnabled AS is_search_qualified,
    human_shifted_state.searchEnabled IS TRUE AND LAG(human_shifted_state.searchEnabled, 1) OVER(PARTITION BY id_session ORDER BY message_index) IS FALSE AS is_the_search_qualification_event,
    human_shifted_state.count AS search_count,
    human_shifted_state.location AS geocoded_location,
    human_shifted_state.askedForFilters AS asked_for_filters,
    human_shifted_state.filters.acceptPets AS accept_pets,
    human_shifted_state.filters.amenities,
    human_shifted_state.filters.area.min AS min_area,
    human_shifted_state.filters.area.max AS max_area,
    human_shifted_state.filters.availability,
    human_shifted_state.filters.bathrooms.min AS min_bathrooms,
    human_shifted_state.filters.bathrooms.max AS max_bathrooms,
    human_shifted_state.filters.bedrooms.min AS min_bedrooms,
    human_shifted_state.filters.bedrooms.max AS max_bedrooms,
    human_shifted_state.filters.businessContext AS business_context,
    human_shifted_state.filters.floor,
    human_shifted_state.filters.installations,
    human_shifted_state.filters.isFurnished AS is_furnished,
    human_shifted_state.filters.location,
    human_shifted_state.filters.locations,
    human_shifted_state.filters.nearSubway AS near_subway,
    human_shifted_state.filters.parkingSpace.min AS min_parking_spaces,
    human_shifted_state.filters.parkingSpace.max AS max_parking_spaces,
    human_shifted_state.filters.price.min AS min_price,
    human_shifted_state.filters.price.max AS max_price,
    human_shifted_state.filters.price.priceType AS price_type,
    human_shifted_state.filters.propertyType AS property_type,
    human_shifted_state.filters.suites.min AS min_suites,
    human_shifted_state.filters.suites.max AS max_suites,
    human_shifted_state.filters.visualAspects AS visual_aspects,
    CONCAT(human_shifted_state.filters.amenities, human_shifted_state.filters.installations) AS amenities_installations,
    human_shifted_state.filters.unsupportedFilters AS unsupported_filters,
    ts_session_created,
    ts_message_sent
FROM processed