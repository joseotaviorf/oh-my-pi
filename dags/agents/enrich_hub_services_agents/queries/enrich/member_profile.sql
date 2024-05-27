WITH member_profile_aud AS (
    SELECT DISTINCT
        mpa.id,
        mpa.id_user,
        COALESCE(mpa.id_parent_member_profile, -1) AS id_parent_member_profile,
        mpa.id_business_unit,
        mpa.rev_end,
        mpa.profile,
        ROW_NUMBER() OVER(PARTITION BY mpa.id ORDER BY mpa.ts_updated DESC) = 1 AS is_last_update,
        mpa.is_active,
        mpa.ts_created AS ts_relationship_started,
        COALESCE(rev.ts_created, LEAD(mpa.ts_created) OVER(PARTITION BY mpa.id ORDER BY mpa.ts_updated)) AS ts_relationship_ended,
        mpa.ts_created,
        mpa.ts_updated,
        mpa.year,
        mpa.month,
        mpa.day
    FROM 
        datalake_hub_services_clean.member_profile_aud AS mpa
    LEFT JOIN 
        datalake_hub_services_clean.rev_info rev 
            ON rev.id = mpa.rev_end
            AND rev.ts_created >= mpa.ts_created
),
member_profile_ended AS (
    SELECT
        mpa.id,
        mpa.id_parent_member_profile,
        LAST(mpa.id_user) AS id_user,
        LAST(mpa.is_active) AS is_active,
        FIRST(mpa.ts_relationship_started) AS ts_relationship_started,
        LAST(mpa.ts_relationship_ended) AS ts_relationship_ended,
        LAST(mpa.ts_updated) AS ts_updated
    FROM
        member_profile_aud AS mpa
    GROUP BY 1, 2
    ORDER BY ts_updated
)
SELECT DISTINCT
    XXHASH64(mpa.id, mpa.id_business_unit, mpa.id_parent_member_profile) AS id_member_relationship,
    mpa.id AS id_member_profile,
    mpe.id_user,
    mpa.id_parent_member_profile,
    mpa_parent.id_user AS id_parent_user,
    mpa.id_business_unit,
    mpa.profile,
    CASE
        WHEN mpe.ts_relationship_ended IS NULL THEN mpe.is_active
        ELSE FALSE
    END AS is_active,
    mpe.ts_relationship_started,
    CASE
        WHEN mpe.ts_relationship_ended IS NULL AND mpe.is_active IS FALSE THEN mpe.ts_updated
        ELSE mpe.ts_relationship_ended
    END AS ts_relationship_ended,
    NOW() AS ts_load
FROM 
    member_profile_aud AS mpa
LEFT JOIN
    member_profile_aud AS mpa_parent
        ON mpa_parent.id = mpa.id_parent_member_profile
        AND mpa_parent.is_last_update IS TRUE
JOIN
    member_profile_ended AS mpe
        ON mpe.id = mpa.id
        AND mpe.id_parent_member_profile = mpa.id_parent_member_profile
