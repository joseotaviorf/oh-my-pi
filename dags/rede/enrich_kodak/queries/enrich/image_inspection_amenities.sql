SELECT
    CASE
        WHEN iig.external_domain = 'HOUSE' THEN iig.id_external_domain
        ELSE h.id
    END AS id_house,
    l.id AS id_lead_3p,
    NULLIF(MAX(ii.room_type = 'pool'), FALSE) AS has_pool,
    NULLIF(MAX(ii.room_type = 'gym' OR ii.room_type = 'exercise_room'), FALSE) AS has_gym,
    NULLIF(MAX(ii.room_type = 'sauna'), FALSE) AS has_sauna,
    NULLIF(MAX(ii.room_type = 'tennis_court' OR ii.room_type = 'basketball_court'), FALSE) AS has_sports_court,
    NULLIF(MAX(ii.room_type = 'game_room' OR ii.room_type = 'playground'), FALSE) AS has_toy_library
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
    room_type IS NOT NULL
GROUP BY 1,2