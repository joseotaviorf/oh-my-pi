WITH owner_history AS (
    SELECT DISTINCT
        id_user,
        id_house
    FROM
        datalake_ebdb_clean.house_aud
),
revisions AS (
    SELECT
        icaa.id_house,
        icaa.rev,
        icaa.rev_type,
        ca.code,
        icaa.has_feature
    FROM
        datalake_ebdb_clean.info_condo_amenities_aud AS icaa
    LEFT JOIN
        datalake_ebdb_clean.condo_amenities AS ca
            ON icaa.id_amenity = ca.id_condo_amenity
    UNION ALL
    SELECT
        id_house,
        rev,
        rev_type,
        'ELEVADOR' AS code,
        has_elevator AS has_feature
    FROM
        datalake_ebdb_clean.house_aud
    QUALIFY
        has_elevator IS DISTINCT FROM LAG(has_elevator) OVER (PARTITION BY id_house ORDER BY rev)
        AND has_elevator IS NOT NULL
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
)
SELECT
    r.id_house,
    h.id_condo_parent,
    ure.id_user AS id_user_revisor,
    r.code,
    CASE
        WHEN hea.rev IS NOT NULL THEN 'Enrichment Module'
        WHEN ure.id_user = oh.id_user THEN 'Owner'
        WHEN u.id_photographer_data IS NOT NULL THEN 'Photographer'
        WHEN u.id_agent IS NOT NULL THEN 'Agent'
        WHEN u.id_affiliates IS NOT NULL THEN 'Affiliate'
        WHEN ure.id_user IS NULL THEN 'System'
        WHEN u.admin_type = 'Admin' THEN 'Admin'
        WHEN u.id = 5979377 THEN 'Supply Processor'
        WHEN u.id IN (293046, 9808622, 7212349) THEN 'Migration'
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
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY h.id, r.code ORDER BY ure.ts_revision DESC) = 1
    AND r.rev_type != 2
