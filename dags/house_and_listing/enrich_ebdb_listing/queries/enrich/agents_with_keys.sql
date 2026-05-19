WITH key_location_aud AS (
    SELECT
        id,
        id_house,
        key_location AS access_type_name,
        mod_authorization,
        entry_model_details AS comments,
        has_opted_keys_with_agent,
        mod_has_opted_keys_with_agent,
        ts_entrance_started AS ts_revision,
        1000*UNIX_TIMESTAMP(ts_entrance_started) AS ts_revision_unix
    FROM
        datalake_ebdb_listing.house_entrance_history
),
key_location_changes AS (
    SELECT
        id_house,
        ts_revision,
        access_type_name,
        MAX(ts_revision) OVER(PARTITION BY id_house, DATE(ts_revision)) = ts_revision AS is_last_status_of_day,
        DATE(ts_revision) AS dt_key_location_started,
        COALESCE(LEAD(DATE(ts_revision)) OVER(PARTITION BY id_house ORDER BY ts_revision),'2100-01-01') AS dt_key_location_ended
    FROM
        key_location_aud
    WHERE
        mod_authorization
),
agent_aud AS (
    WITH old AS (
        SELECT
            haa.id_house,
            CASE haa.relation_type
                WHEN 'KEY_HOLDER' THEN TRUE
                ELSE FALSE
            END AS is_keys_with_agent_eligible,
            FROM_UNIXTIME(ure.ts_revision/1000) AS ts_revision
        FROM
            datalake_ebdb_clean.user_revision_entity AS ure
        JOIN
            datalake_ebdb_clean.house_agent_aud AS haa
                ON haa.rev = ure.id
        WHERE
            FROM_UNIXTIME(ure.ts_revision/1000)::DATE < '2025-11-01'
    ),
    new AS (
        SELECT
            heh.id_house,
            IF(heh.event_type = 'KEY_HOLDER_DEALLOCATED', FALSE, TRUE) AS is_keys_with_agent_eligible,
            heh.ts_entrance_started AS ts_revision
        FROM
            datalake_ebdb_listing.house_entrance_history AS heh
        WHERE
            ts_entrance_started::DATE >= '2025-11-01'
            AND key_location = 'AGENT'
    )
    SELECT
        id_house,
        is_keys_with_agent_eligible,
        ts_revision
    FROM
        old
    UNION ALL
    SELECT
        id_house,
        is_keys_with_agent_eligible,
        ts_revision
    FROM
        new
),
attributions_context AS (
    WITH old AS (
        SELECT
            MD5(CAST(hakt.id AS STRING)) AS id,
            hakt.id_agent,
            hakt.id_house,
            hakt.comments,
            'attributions_context' AS query_context,
            CASE
                WHEN hakt.status = 'NOT_DELIVERED' THEN 'KEY_HOLDER_ALLOCATED'
                WHEN hakt.status = 'DELIVERED' THEN 'KEY_HOLDER_VALIDATED'
                WHEN hakt.status = 'RETURNED' THEN 'KEY_HOLDER_DEALLOCATED'
                ELSE NULL
            END AS status,
            FROM_UNIXTIME(ure.ts_revision/1000) AS ts_revision,
            ts_revision AS ts_revision_unix
        FROM
            datalake_ebdb_clean.house_agent_key_tracking_aud AS hakt
        JOIN
            datalake_ebdb_clean.user_revision_entity AS ure
                ON hakt.rev = ure.id
        WHERE
            FROM_UNIXTIME(ure.ts_revision/1000)::DATE < '2025-06-17'
    ),
    new AS (
        SELECT
            MD5(CAST(heh.id AS STRING)) AS id,
            user.id_agent,
            heh.id_house,
            heh.entry_model_details AS comments,
            'attributions_context' AS query_context,
            heh.event_type AS status,
            heh.ts_entrance_started AS ts_revision,
            1000*UNIX_TIMESTAMP(heh.ts_entrance_started) AS ts_revision_unix
        FROM
            datalake_ebdb_listing.house_entrance_history AS heh
        LEFT JOIN
            datalake_ebdb_clean.user
                ON heh.key_holder_identifier = user.id
        WHERE
            heh.ts_entrance_started::DATE >= '2025-06-17'
            AND heh.key_location = 'AGENT'
            AND heh.event_type IN ('KEY_HOLDER_ALLOCATED', 'KEY_HOLDER_VALIDATED', 'KEY_HOLDER_DEALLOCATED')
    )
    SELECT
        id,
        id_agent,
        id_house,
        comments,
        query_context,
        status,
        ts_revision,
        ts_revision_unix
    FROM
        old
    UNION ALL
    SELECT
        id,
        id_agent,
        id_house,
        comments,
        query_context,
        status,
        ts_revision,
        ts_revision_unix
    FROM
        new
),
-- Associate each revision with its corresponding listing version
-- Criterea being closer to listing version start or end date
merged_key_status AS (
    SELECT
        id,
        -1 AS id_agent,
        id_house,
        comments,
        'optin_context' AS query_context,
        CASE
            WHEN has_opted_keys_with_agent = TRUE THEN 'OPT_IN'
            ELSE 'NO_OPT_IN'
        END AS status,
        ts_revision,
        ts_revision_unix
    FROM
        key_location_aud
    WHERE
        mod_has_opted_keys_with_agent = TRUE
        AND has_opted_keys_with_agent IS NOT NULL
    UNION
    SELECT
        id,
        id_agent,
        id_house,
        comments,
        query_context,
        status,
        ts_revision,
        ts_revision_unix
    FROM
        attributions_context
),
key_status_listings AS (
    SELECT
        mks.id,
        mks.id_agent,
        mks.id_house,
        dhl.id_house_listing,
        mks.comments,
        mks.query_context,
        mks.status,
        LEAST(
            CASE
                WHEN ts_listing_version_start IS NOT NULL THEN ABS(1000*UNIX_TIMESTAMP(ts_listing_version_start) - ts_revision_unix)
            END,
            CASE
                WHEN ts_listing_version_end IS NOT NULL THEN ABS(1000*UNIX_TIMESTAMP(ts_listing_version_end - INTERVAL 7 DAYS) - ts_revision_unix)
            END
        ) AS min_diff_listing,
        CASE
            WHEN RIGHT(dhl.id_house_listing, 3) = '000' THEN TRUE
            ELSE FALSE
        END AS is_first_listing,
        ts_listing_version_start,
        ts_revision
    FROM
        merged_key_status AS mks
    JOIN
        datalake_ebdb_listing.house_listing dhl
            USING(id_house)
),
-- keep closer listing
keys_closer_listings AS (
    SELECT DISTINCT
        FIRST_VALUE(id_agent, TRUE) OVER(PARTITION BY id_house_listing ORDER BY ts_revision DESC) AS id_agent,
        id_house,  -- check if id_agent can be 0
        id_house_listing,
        comments,
        status,
        ROW_NUMBER() OVER(PARTITION BY query_context, id, ts_revision ORDER BY is_first_listing, min_diff_listing) AS row_n,
        ts_listing_version_start,
        ts_revision
    FROM
        key_status_listings
),
keys_attributions AS (
    SELECT
        id_agent,
        id_house_listing,
        COLLECT_SET(IF(id_agent > 0, id_agent, NULL)) AS id_agents,
        MAX(status = 'KEY_HOLDER_ALLOCATED') AS has_keys_with_agent_attributed,
        MAX(status = 'KEY_HOLDER_VALIDATED') AS has_keys_with_agent_delivered,
        MAX(status = 'KEY_HOLDER_DEALLOCATED') AS has_keys_with_agent_returned,
        MAX(IF(comments rlike '(?i)chave recebida durante visita ao imóvel', TRUE, FALSE)) AS is_delivered_on_another_listing,
        MAX(
            CASE
                WHEN status = 'OPT_IN' THEN TRUE
                WHEN status = 'NO_OPT_IN' THEN FALSE
            END
        ) AS is_keys_with_agent_opt_in,
        MIN(IF(status = 'KEY_HOLDER_ALLOCATED', ts_revision,NULL)) AS ts_attributed,
        MIN(IF(status = 'KEY_HOLDER_VALIDATED', ts_revision,NULL)) AS ts_delivered,
        MIN(IF(status IN ('OPT_IN', 'NO_OPT_IN'), ts_revision,NULL)) AS ts_optin,
        ts_listing_version_start AS ts_publicated,
        MIN(IF(status = 'KEY_HOLDER_DEALLOCATED', ts_revision,NULL)) AS ts_returned

    FROM
        keys_closer_listings
    WHERE
        row_n = 1
    GROUP BY 1, 2, 12
),
non_doorman_listing AS (
    SELECT DISTINCT
        hl.id_house,
        hl.id_house_listing,
        hl.country_code,
        h.doorman_type,
        FIRST_VALUE(klc.access_type_name) OVER (PARTITION BY hl.id_house_listing ORDER BY klc.ts_revision) AS first_key_location,
        h.key_location AS house_key_location,
        LAST_VALUE(klc.access_type_name) OVER (PARTITION BY hl.id_house_listing ORDER BY klc.ts_revision RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_key_location,
        h.occupant_type AS who_is_living,
        h.is_for_sale,
        IF(h.id_user = h.id_user_registrant, TRUE, FALSE) AS is_fss,
        MAX(aa.is_keys_with_agent_eligible) OVER(PARTITION BY hl.id_house_listing) AS is_keys_with_agent_eligible,
        hl.ts_contract_signed AS ts_contract_signed,
        hl.ts_listing_version_start,
        hl.ts_listing_version_end
    FROM
        datalake_ebdb_listing.house_listing hl
    JOIN
        datalake_ebdb_listing.house h
            ON hl.id_house = h.id
    LEFT JOIN
        key_location_changes klc
            ON klc.id_house = hl.id_house
            AND (
                 (klc.dt_key_location_started >= DATE(COALESCE(ts_listing_version_start, '1900-01-01')) AND klc.dt_key_location_started < DATE(COALESCE(ts_listing_version_end, '2100-01-01')))
                 OR (DATE(COALESCE(ts_listing_version_start, '1900-01-01')) >= klc.dt_key_location_started AND DATE(COALESCE(ts_listing_version_start, '1900-01-01')) < klc.dt_key_location_ended)
                )
            AND klc.is_last_status_of_day = True
    LEFT JOIN
        agent_aud AS aa
            ON hl.id_house = aa.id_house
            AND aa.ts_revision BETWEEN COALESCE(hl.ts_listing_version_start, aa.ts_revision) AND COALESCE(hl.ts_listing_version_end, aa.ts_revision)
)
SELECT DISTINCT
    ka.id_agent,
    ndl.id_house,
    ndl.id_house_listing,
    CAST(ka.id_agents AS STRING) AS all_id_agents,
    COALESCE(user.country_code, ndl.country_code) AS country_code,
    ndl.first_key_location,
    ndl.house_key_location,
    ndl.last_key_location,
    ndl.who_is_living,
    CASE
        WHEN ndl.ts_contract_signed IS NOT NULL AND ka.has_keys_with_agent_delivered THEN CAST((TO_UNIX_TIMESTAMP(ka.ts_returned) - TO_UNIX_TIMESTAMP(ndl.ts_contract_signed))/86400 AS DECIMAL(7,2))
    END AS days_cs_to_return,
    CAST((TO_UNIX_TIMESTAMP(ka.ts_attributed) - TO_UNIX_TIMESTAMP(ka.ts_publicated))/86400 AS DECIMAL(7,2)) AS days_publication_to_attribution,
    ka.has_keys_with_agent_attributed,
    ka.has_keys_with_agent_delivered,
    ka.has_keys_with_agent_returned,
    ka.is_delivered_on_another_listing,
    ndl.is_fss,
    ka.is_keys_with_agent_opt_in,
    CASE
        WHEN ndl.is_keys_with_agent_eligible = TRUE THEN TRUE
        WHEN ndl.house_key_location IN ('OWNER','NONE')
                AND ndl.doorman_type IN ('NaoHaPorteiro', 'Noturno')
                AND ndl.who_is_living = 'Empty'
                AND ndl.is_for_sale = FALSE THEN TRUE
        ELSE FALSE
    END AS is_keys_with_agent_eligible,
    CASE
        WHEN ndl.ts_contract_signed IS NOT NULL AND ka.has_keys_with_agent_delivered THEN (TO_UNIX_TIMESTAMP(ka.ts_returned) - TO_UNIX_TIMESTAMP(ndl.ts_contract_signed))/86400 <= 3
    END AS is_returned_on_time,
    CAST(ka.ts_attributed AS TIMESTAMP) AS ts_attributed,
    CAST(ndl.ts_contract_signed AS TIMESTAMP) AS ts_contract_signed,
    CAST(ka.ts_delivered AS TIMESTAMP) AS ts_delivered,
    CAST(ndl.ts_listing_version_start AS TIMESTAMP) AS ts_listing_version_start,
    CAST(ndl.ts_listing_version_end AS TIMESTAMP) AS ts_listing_version_end,
    CAST(ka.ts_optin AS TIMESTAMP) AS ts_optin,
    CAST(ka.ts_publicated AS TIMESTAMP) AS ts_publicated,
    CAST(ka.ts_returned AS TIMESTAMP) AS ts_returned
FROM
    non_doorman_listing AS ndl
LEFT JOIN
    keys_attributions ka
        USING(id_house_listing)
LEFT JOIN
    datalake_ebdb_country.user
        ON user.id_user = ka.id_agent
