WITH ts_key_location_aud AS (
    SELECT
        ata.id_house,
        ata.rev AS key_location_rev,
        aat.name AS access_type_name,
        ata.has_opted_keys_with_agent,
        FROM_UNIXTIME(ure.ts_revision/1000) AS ts_key_location_rev
    FROM
        datalake_ebdb_clean.access_type_aud ata
    JOIN
        datalake_ebdb_clean.access_authorization_type AS aat
            ON ata.id_authorization = aat.id
    JOIN
        datalake_ebdb_clean.user_revision_entity AS ure
            ON ata.rev = ure.id
),
ts_agent_aud AS (
    SELECT
        haa.id_house,
        haa.rev AS agent_rev,
        haa.relation_type,
        CASE haa.relation_type
            WHEN 'KEY_HOLDER' THEN TRUE
            ELSE FALSE
        END AS is_keys_with_agent_eligible,
        FROM_UNIXTIME(ure.ts_revision/1000) AS ts_agent_rev
    FROM
        datalake_ebdb_clean.user_revision_entity ure
    JOIN
        datalake_ebdb_clean.house_agent_aud haa
            ON haa.rev = ure.id
),
non_doorman_listing AS (
    SELECT
        hl.id_house,
        hl.id_house_listing,
        h.doorman_type,
        FIRST_VALUE(tkla.access_type_name) OVER (PARTITION BY hl.id_house_listing ORDER BY tkla.key_location_rev) AS first_key_location,
        h.key_location AS house_key_location,
        LAST_VALUE(tkla.access_type_name) OVER (PARTITION BY hl.id_house_listing ORDER BY tkla.key_location_rev RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_key_location,
        h.occupant_type AS who_is_living,
        IF(hakt.status = 'NOT_DELIVERED', true, false) AS has_keys_with_agent_attributed,
        IF(hakt.status = 'DELIVERED', true, false) AS has_keys_with_agent_delivered,
        MAX(taa.is_keys_with_agent_eligible) OVER(PARTITION BY hl.id_house_listing) AS is_keys_with_agent_eligible,
        MAX(tkla.has_opted_keys_with_agent) OVER (PARTITION BY hl.id_house_listing) AS is_keys_with_agent_opt_in,
        IF(hakt.status = 'RETURNED', true, false) AS has_keys_with_agent_returned,
        h.is_for_sale,
        hl.ts_listing_version_start,
        hl.ts_listing_version_end
    FROM
        datalake_ebdb_listing.house_listing hl
    JOIN
        datalake_ebdb_listing.house h
            ON hl.id_house = h.id
    LEFT JOIN
        ts_key_location_aud tkla
            ON tkla.id_house = hl.id_house
            AND tkla.ts_key_location_rev BETWEEN COALESCE(hl.ts_listing_version_start, tkla.ts_key_location_rev) AND COALESCE(hl.ts_listing_version_end, tkla.ts_key_location_rev)
    LEFT JOIN
        ts_agent_aud AS taa
            ON hl.id_house = taa.id_house
            AND taa.ts_agent_rev BETWEEN COALESCE(hl.ts_listing_version_start, taa.ts_agent_rev) AND COALESCE(hl.ts_listing_version_end, taa.ts_agent_rev)
    LEFT JOIN
        datalake_ebdb_clean.house_agent_key_tracking hakt
            ON hl.id_house = hakt.id_house
            AND hakt.ts_updated BETWEEN COALESCE(hl.ts_listing_version_start, hakt.ts_updated) AND COALESCE(hl.ts_listing_version_end, hakt.ts_updated)
)
SELECT DISTINCT
    ndl.id_house,
    ndl.id_house_listing,
    ndl.first_key_location,
    ndl.house_key_location,
    ndl.last_key_location,
    ndl.who_is_living,
    ndl.has_keys_with_agent_attributed,
    ndl.has_keys_with_agent_delivered,
    ndl.has_keys_with_agent_returned,
    ndl.is_keys_with_agent_opt_in,
    CASE
        WHEN ndl.is_keys_with_agent_eligible = TRUE THEN TRUE
        WHEN ndl.house_key_location IN ('OwnerPresent','None') 
                AND ndl.doorman_type IN ('NaoHaPorteiro', 'Noturno')
                AND ndl.who_is_living = 'Empty' 
                AND ndl.is_for_sale = FALSE THEN TRUE
        ELSE FALSE
    END AS is_keys_with_agent_eligible,
    ndl.ts_listing_version_start,
    ndl.ts_listing_version_end
FROM
    non_doorman_listing AS ndl