WITH amenities_aud AS (
    SELECT
        LAST_VALUE(i.id_house, TRUE) OVER (PARTITION BY i.id_info_amenity ORDER BY i.rev) AS id_house,
        LAST_VALUE(a.id, TRUE) OVER (PARTITION BY i.id_info_amenity ORDER BY i.rev) AS id_amenity,
        r.id_user,
        i.rev,
        i.rev_type,
        i.has_feature,
        FALSE AS is_condo_amenity,
        r.ts_revision AS ts_change
    FROM
        datalake_ebdb_clean.info_amenities_aud AS i
    LEFT JOIN 
        datalake_ebdb_clean.amenities AS a
            ON i.id_amenity = a.id
    JOIN 
        datalake_ebdb_user.user_revision_entity AS r
            ON i.rev = r.id
),
amenities_current AS ( -- To make sure the last row of this table matches the present
    SELECT
        i.id_house,
        a.id AS id_amenity,
        NULL AS id_user,
        NULL AS rev,
        1 AS rev_type,
        i.has_characteristic AS has_feature,
        FALSE AS is_condo_amenity,
        COALESCE(i.ts_updated, NOW()) AS ts_change
    FROM
        datalake_ebdb_clean.info_amenities AS i
    JOIN 
        datalake_ebdb_clean.amenities AS a
            ON i.id_amenities = a.id
),
condo_amenities_aud AS (
    SELECT
        LAST_VALUE(i.id_house, TRUE) OVER (PARTITION BY i.id_info_condo_amenity ORDER BY i.rev) AS id_house,
        LAST_VALUE(a.id_condo_amenity, TRUE) OVER (PARTITION BY i.id_info_condo_amenity ORDER BY i.rev) AS id_amenity,
        r.id_user,
        i.rev,
        i.rev_type,
        i.has_feature,
        TRUE AS is_condo_amenity,
        r.ts_revision AS ts_change
    FROM
        datalake_ebdb_clean.info_condo_amenities_aud AS i
    LEFT JOIN 
        datalake_ebdb_clean.condo_amenities AS a
            ON i.id_amenity = a.id_condo_amenity
    JOIN 
        datalake_ebdb_user.user_revision_entity AS r
            ON i.rev = r.id
    UNION ALL
    SELECT -- Adding elevator, since it's not part of the amenities table
        ha.id_house,
        0 AS id_amenity,
        ure.id_user,
        ha.rev,
        ha.rev_type,
        ha.has_elevator AS has_feature,
        TRUE AS is_condo_amenity,
        ure.ts_revision
    FROM
        datalake_ebdb_clean.house_aud AS ha
    JOIN
        datalake_ebdb_user.user_revision_entity AS ure
            ON ha.rev = ure.id
),
condo_amenities_current AS ( -- To make sure the last row of this table matches the present
    SELECT
        i.id_house,
        a.id_condo_amenity AS id_amenity,
        NULL AS id_user,
        NULL AS rev,
        1 AS rev_type,
        i.has_characteristic AS has_feature,
        TRUE AS is_condo_amenity,
        COALESCE(i.ts_updated, NOW()) AS ts_change
    FROM
        datalake_ebdb_clean.info_condo_amenities AS i
    JOIN 
        datalake_ebdb_clean.condo_amenities AS a
            ON i.id_condo_amenities = a.id_condo_amenity
    UNION ALL
    SELECT -- Elevator
        id AS id_house,
        0 AS id_amenity,
        NULL AS id_user,
        NULL AS rev,
        1 AS rev_type,
        has_elevator AS has_feature,
        TRUE AS is_condo_amenity,
        COALESCE(ts_updated, NOW()) AS ts_change
    FROM
        datalake_ebdb_clean.house
),
amenities_full_log AS (
    SELECT *
    FROM
        amenities_aud
    UNION ALL
    SELECT *
    FROM
        amenities_current
    UNION ALL
    SELECT *
    FROM 
        condo_amenities_aud
    UNION ALL
    SELECT *
    FROM 
        condo_amenities_current
),
-- Particularly in the first few years of operation, instead of updating existing rows, we would delete every single
-- row and then create new ones after. Here, we're removing changes from the aud that are replaced by another change in less than a minute
removed_redundancies AS (
    SELECT *
    FROM
        amenities_full_log   
    QUALIFY
        COALESCE(UNIX_TIMESTAMP(
            LEAD(ts_change) OVER(
                PARTITION BY id_house, rev IS NOT NULL, id_amenity, is_condo_amenity
                ORDER BY ts_change, rev_type DESC -- rev_type = 2 (deletion) will come first, so its row would be removed if the deletion is simultaneous with an insert
            )
        ) - UNIX_TIMESTAMP(ts_change), 61) > 60
        OR has_feature IS NOT DISTINCT FROM LEAD(has_feature) OVER( -- Unless, the next change has literally the same value. In that, we will consider the first one
            PARTITION BY id_house, rev IS NOT NULL, id_amenity, is_condo_amenity
            ORDER BY ts_change, rev_type DESC
        )
),
deduped_amenities AS (
    SELECT *
    FROM
        removed_redundancies
    QUALIFY
        LAG(has_feature) OVER (PARTITION BY id_house, id_amenity, is_condo_amenity ORDER BY rev NULLS LAST, rev_type DESC) IS DISTINCT FROM has_feature
)
SELECT
    da.id_house,
    da.id_user,
    da.id_amenity,
    da.rev,
    da.rev_type,
    da.has_feature,
    da.is_condo_amenity,
    CASE 
      WHEN da.rev IS NOT NULL 
        OR ur.id_user = 293046 THEN TRUE 
      ELSE FALSE
    END AS is_atlas_update,
    da.ts_change,
    LEAD(da.ts_change) OVER (PARTITION BY da.id_house, da.id_amenity, da.is_condo_amenity ORDER BY da.rev NULLS LAST, da.rev_type DESC) AS ts_next_change
FROM
    deduped_amenities da

LEFT JOIN 
  datalake_ebdb_clean.user_revision_entity ur
    ON da.rev = ur.id
