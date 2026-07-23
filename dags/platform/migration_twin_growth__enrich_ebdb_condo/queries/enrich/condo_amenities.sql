WITH owner_history AS (
    SELECT DISTINCT
        id_user,
        id_house
    FROM
        datalake_ebdb_clean.house_aud
),
revisions AS (
    SELECT
        ach.id_house,
        ach.rev,
        ach.rev_type,
        a.code,
        ach.has_feature
    FROM
        datalake_ebdb_amenities.amenity_change_history AS ach
    JOIN
        datalake_ebdb_amenities.amenity AS a
            ON ach.id_amenity = a.id_amenity
            AND ach.is_condo_amenity = a.is_condo_amenity
    WHERE
        ach.is_condo_amenity
    UNION ALL
    SELECT
        id_house,
        rev,
        rev_type,
        'PORTARIA_24H' AS code,
        doorman_type = 'horas24' AS has_feature
    FROM
        datalake_ebdb_clean.house_aud
    QUALIFY
        doorman_type IS DISTINCT FROM LAG(doorman_type) OVER (PARTITION BY id_house ORDER BY rev)
        AND doorman_type IS NOT NULL
),
revisions_with_role AS (
    SELECT
        r.id_house,
        h.id_condo_parent,
        ure.id_user AS id_user_revisor,
        r.code,
        r.rev_type,
        CASE
            WHEN hea.rev IS NOT NULL OR u.id = 293046 THEN 'Enrichment Module'
            WHEN ure.id_user = oh.id_user THEN 'Owner'
            WHEN u.id_photographer_data IS NOT NULL THEN 'Photographer'
            WHEN u.id_agent IS NOT NULL THEN 'Agent'
            WHEN u.id_affiliates IS NOT NULL THEN 'Affiliate'
            WHEN ure.id_user IS NULL THEN 'System'
            WHEN u.admin_type = 'Admin' THEN 'Admin'
            WHEN u.id IN (5979377, 13162050) THEN 'Supply Processor'
            WHEN u.id IN (9808622, 7212349) THEN 'Migration'
            WHEN u.email LIKE '%@quintoandar%' THEN 'Other Internal'
            ELSE 'Other External'
        END AS revisor,
        r.has_feature,
        ure.ts_revision
    FROM
        revisions AS r
    LEFT JOIN
        datalake_ebdb_clean.house AS h
            ON r.id_house = h.id
    JOIN
        datalake_ebdb_user.user_revision_entity AS ure
            ON r.rev = ure.id
    LEFT JOIN
        datalake_ebdb_clean.`user` AS u
            ON ure.id_user = u.id
    LEFT JOIN
        datalake_ebdb_clean.house_enrichment_aud AS hea
            ON r.id_house = hea.id_house
            AND r.rev = hea.rev
    LEFT JOIN
        owner_history AS oh
            ON oh.id_house = r.id_house
            AND oh.id_user = ure.id_user
)
SELECT
    id_house,
    id_condo_parent,
    id_user_revisor,
    code,
    revisor,
    has_feature,
    ts_revision
FROM
    revisions_with_role
WHERE
    revisor != 'Enrichment Module' -- This is for Vespúcio not to fall in a loop, causing updates which themselves affect Vespúcio
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_house, code ORDER BY ts_revision DESC) = 1
    AND rev_type != 2
