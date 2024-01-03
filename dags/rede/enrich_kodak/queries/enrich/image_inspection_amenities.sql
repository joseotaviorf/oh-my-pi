WITH room_types AS (
    SELECT
        CASE
            WHEN iig.external_domain = 'HOUSE' THEN iig.id_external_domain
            ELSE h.id
        END AS id_house,
        l.id AS id_lead_3p,
        ii.room_type
    FROM
        datalake_kodak_clean.image_inspection AS ii
    JOIN
        datalake_kodak_clean.image_inspection_group AS iig
            ON ii.id_group = iig.id
    LEFT JOIN
        datalake_brokers_supply_processor.lead_3p AS l
            ON iig.id_external_domain = l.uuid_lead
            AND iig.external_domain = 'LEAD3P'
    LEFT JOIN
        datalake_ebdb_clean.house AS h
            ON l.uuid_lead = h.id_external
    WHERE
        ii.room_type IS NOT NULL
)
SELECT
    MIN(id_house) AS id_house,
    MIN(id_lead_3p) AS id_lead_3p,
    NULLIF(MAX(room_type = 'pool'), FALSE) AS has_pool,
    NULLIF(MAX(room_type = 'gym' OR room_type = 'exercise_room'), FALSE) AS has_gym,
    NULLIF(MAX(room_type = 'sauna'), FALSE) AS has_sauna,
    NULLIF(MAX(room_type = 'tennis_court' OR room_type = 'basketball_court'), FALSE) AS has_sports_court,
    NULLIF(MAX(room_type = 'game_room' OR room_type = 'playground'), FALSE) AS has_toy_library,
    NULLIF(MAX(room_type = 'balcony'), FALSE) AS has_balcony,
    NULLIF(MAX(room_type = 'walk_in_closet'), FALSE) AS has_walk_in_closet,
    NULLIF(MAX(room_type = 'mountain_view' OR room_type = 'city_view'), FALSE) AS has_unobstructed_view
FROM
    room_types
GROUP BY
    COALESCE(id_house, id_lead_3p)
