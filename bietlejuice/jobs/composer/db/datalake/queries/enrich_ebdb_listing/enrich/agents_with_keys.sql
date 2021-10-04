WITH key_location_aud AS (
    SELECT
        ata.id,
        ata.id_house,
        ata.rev AS key_location_rev,
        aat.name AS access_type_name,
        ata.additional_info AS comments,
        ata.has_opted_keys_with_agent,
        ata.mod_has_opted_keys_with_agent,
        FROM_UNIXTIME(ure.ts_revision/1000) AS ts_revision,
        ts_revision AS ts_revision_unix
    FROM
        datalake_ebdb_clean.access_type_aud ata
    JOIN
        datalake_ebdb_clean.access_authorization_type AS aat
            ON ata.id_authorization = aat.id
    JOIN
        datalake_ebdb_clean.user_revision_entity AS ure
            ON ata.rev = ure.id
),
agent_aud AS (
    SELECT
        haa.id_house,
        haa.rev AS agent_rev,
        haa.relation_type,
        CASE haa.relation_type
            WHEN 'KEY_HOLDER' THEN TRUE
            ELSE FALSE
        END AS is_keys_with_agent_eligible,
        FROM_UNIXTIME(ure.ts_revision/1000) AS ts_revision
    FROM
        datalake_ebdb_clean.user_revision_entity ure
    JOIN
        datalake_ebdb_clean.house_agent_aud haa
            ON haa.rev = ure.id
),
-- Associate each revision with its corresponding listing version
-- Criterea being closer to listing version start or end date
merged_key_status AS (
    SELECT
        id,
        -1 AS id_agent,
        id_house,
        key_location_rev AS rev,
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
        hakt.id,
        hakt.id_agent,
        hakt.id_house,
        hakt.rev,
        hakt.comments,
        'attributions_context' AS query_context,
        hakt.status,
        FROM_UNIXTIME(ure.ts_revision/1000) AS ts_revision,
        ts_revision AS ts_revision_unix
    FROM
        datalake_ebdb_clean.house_agent_key_tracking_aud AS hakt
    JOIN
        datalake_ebdb_clean.user_revision_entity AS ure
            ON hakt.rev = ure.id
),
key_status_listings AS (
    SELECT
        mks.id, 
        mks.id_agent,
        mks.id_house,
        dhl.id_house_listing,
        mks.rev,
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
        FIRST_VALUE(id_agent, TRUE) OVER(PARTITION BY id_house_listing ORDER BY rev DESC) AS id_agent,
        id_house,  -- check if id_agent can be 0
        id_house_listing,
        comments,
        status,
        ROW_NUMBER() OVER(PARTITION BY query_context, id, rev ORDER BY is_first_listing, min_diff_listing) AS row_n,
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
        MAX(status = 'NOT_DELIVERED') AS has_keys_with_agent_attributed,
        MAX(status = 'DELIVERED') AS has_keys_with_agent_delivered,
        MAX(status = 'RETURNED') AS has_keys_with_agent_returned,
        MAX(IF(comments rlike '(?i)chave recebida durante visita ao imóvel', TRUE, FALSE)) AS is_delivered_on_another_listing,
        MAX(
            CASE
                WHEN status = 'OPT_IN' THEN TRUE
                WHEN status = 'NO_OPT_IN' THEN FALSE
            END 
        ) AS is_keys_with_agent_opt_in,
        MIN(IF(status = 'NOT_DELIVERED', DATE(ts_revision),NULL)) AS dt_attributed,
        MIN(IF(status = 'DELIVERED', DATE(ts_revision),NULL)) AS dt_delivered,
        MIN(IF(status IN ('OPT_IN', 'NO_OPT_IN'), DATE(ts_revision),NULL)) AS dt_optin,
        DATE(ts_listing_version_start) AS dt_publicated,
        MIN(IF(status = 'RETURNED', DATE(ts_revision),NULL)) AS dt_returned

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
        h.doorman_type,
        FIRST_VALUE(kla.access_type_name) OVER (PARTITION BY hl.id_house_listing ORDER BY kla.key_location_rev) AS first_key_location,
        h.key_location AS house_key_location,
        LAST_VALUE(kla.access_type_name) OVER (PARTITION BY hl.id_house_listing ORDER BY kla.key_location_rev RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_key_location,
        h.occupant_type AS who_is_living,
        MAX(aa.is_keys_with_agent_eligible) OVER(PARTITION BY hl.id_house_listing) AS is_keys_with_agent_eligible,
        h.is_for_sale,
        hl.ts_listing_version_start,
        hl.ts_listing_version_end
    FROM
        datalake_ebdb_listing.house_listing hl
    JOIN
        datalake_ebdb_listing.house h
            ON hl.id_house = h.id
    LEFT JOIN
        key_location_aud kla
            ON kla.id_house = hl.id_house
            AND kla.ts_revision BETWEEN COALESCE(hl.ts_listing_version_start, kla.ts_revision) AND COALESCE(hl.ts_listing_version_end, kla.ts_revision)
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
    ndl.first_key_location,
    ndl.house_key_location,
    ndl.last_key_location,
    ndl.who_is_living,
    ka.has_keys_with_agent_attributed,
    ka.has_keys_with_agent_delivered,
    ka.has_keys_with_agent_returned,
    ka.is_delivered_on_another_listing,
    ka.is_keys_with_agent_opt_in,
    CASE
        WHEN ndl.is_keys_with_agent_eligible = TRUE THEN TRUE
        WHEN ndl.house_key_location IN ('OwnerPresent','None') 
                AND ndl.doorman_type IN ('NaoHaPorteiro', 'Noturno')
                AND ndl.who_is_living = 'Empty' 
                AND ndl.is_for_sale = FALSE THEN TRUE
        ELSE FALSE
    END AS is_keys_with_agent_eligible,
    ka.dt_attributed,
    ka.dt_delivered,
    ka.dt_optin,
    ka.dt_publicated,
    ka.dt_returned,
    ndl.ts_listing_version_start,
    ndl.ts_listing_version_end
FROM
    non_doorman_listing AS ndl
LEFT JOIN
    keys_attributions ka
        USING(id_house_listing)