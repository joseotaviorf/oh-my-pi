WITH amenities_aud AS (
  SELECT
    LAST_VALUE(i.id_house) IGNORE NULLS OVER (PARTITION BY i.id_info_amenity ORDER BY i.rev) AS id_house,
    LAST_VALUE(a.id) IGNORE NULLS OVER (PARTITION BY i.id_info_amenity ORDER BY i.rev) AS id_amenity,
    r.id_user,
    i.rev,
    i.rev_type,
    i.has_feature,
    FALSE AS is_condo_amenity,
    r.ts_revision AS ts_change
  FROM datalake_ebdb_clean.info_amenities_aud AS i
  LEFT JOIN datalake_ebdb_clean.amenities AS a
    ON i.id_amenity = a.id
  JOIN datalake_ebdb_user.user_revision_entity AS r
    ON i.rev = r.id
), amenities_current AS (
  -- info_amenities carries duplicate (id_house, id_amenity) rows for a small fraction of
  -- houses (source data-quality issue, not an audit event). Left undeduped, two such rows
  -- with NULL ts_updated both fall back to the same NOW() literal (evaluated once per query
  -- run) and tie on (id_house, NOT rev IS NULL, id_amenity, is_condo_amenity, ts_change,
  -- rev_type) with rev/id_user also NULL on both sides -- a tie no rev-based ORDER BY can
  -- break. Keep exactly one deterministic row per (id_house, id_amenity) instead.
  SELECT
    id_house,
    id_amenity,
    id_user,
    rev,
    rev_type,
    has_feature,
    is_condo_amenity,
    ts_change
  FROM (
    SELECT
      i.id_house,
      a.id AS id_amenity,
      NULL AS id_user,
      NULL AS rev,
      1 AS rev_type,
      i.has_characteristic AS has_feature,
      FALSE AS is_condo_amenity,
      COALESCE(i.ts_updated, NOW()) AS ts_change,
      ROW_NUMBER() OVER (
        PARTITION BY i.id_house, a.id
        ORDER BY i.ts_updated DESC NULLS LAST, i.ts_created DESC NULLS LAST, i.id DESC
      ) AS rn
    FROM datalake_ebdb_clean.info_amenities AS i
    JOIN datalake_ebdb_clean.amenities AS a
      ON i.id_amenities = a.id
  ) AS deduped_current
  WHERE
    rn = 1
), condo_amenities_aud AS (
  SELECT
    LAST_VALUE(i.id_house) IGNORE NULLS OVER (PARTITION BY i.id_info_condo_amenity ORDER BY i.rev) AS id_house,
    LAST_VALUE(a.id_condo_amenity) IGNORE NULLS OVER (PARTITION BY i.id_info_condo_amenity ORDER BY i.rev) AS id_amenity,
    r.id_user,
    i.rev,
    i.rev_type,
    i.has_feature,
    TRUE AS is_condo_amenity,
    r.ts_revision AS ts_change
  FROM datalake_ebdb_clean.info_condo_amenities_aud AS i
  LEFT JOIN datalake_ebdb_clean.condo_amenities AS a
    ON i.id_amenity = a.id_condo_amenity
  JOIN datalake_ebdb_user.user_revision_entity AS r
    ON i.rev = r.id
  UNION ALL
  /* Adding elevator, since it's not part of the amenities table */
  SELECT
    ha.id_house,
    0 AS id_amenity,
    ure.id_user,
    ha.rev,
    ha.rev_type,
    ha.has_elevator AS has_feature,
    TRUE AS is_condo_amenity,
    ure.ts_revision
  FROM datalake_ebdb_clean.house_aud AS ha
  JOIN datalake_ebdb_user.user_revision_entity AS ure
    ON ha.rev = ure.id
), condo_amenities_current AS (
  -- Same duplicate-current-row issue as amenities_current (see comment there), mirrored on
  -- the condo side in info_condo_amenities.
  SELECT
    id_house,
    id_amenity,
    id_user,
    rev,
    rev_type,
    has_feature,
    is_condo_amenity,
    ts_change
  FROM (
    SELECT
      i.id_house,
      a.id_condo_amenity AS id_amenity,
      NULL AS id_user,
      NULL AS rev,
      1 AS rev_type,
      i.has_characteristic AS has_feature,
      TRUE AS is_condo_amenity,
      COALESCE(i.ts_updated, NOW()) AS ts_change,
      ROW_NUMBER() OVER (
        PARTITION BY i.id_house, a.id_condo_amenity
        ORDER BY i.ts_updated DESC NULLS LAST, i.ts_created DESC NULLS LAST, i.id_info_condo_amenity DESC
      ) AS rn
    FROM datalake_ebdb_clean.info_condo_amenities AS i
    JOIN datalake_ebdb_clean.condo_amenities AS a
      ON i.id_condo_amenities = a.id_condo_amenity
  ) AS deduped_current
  WHERE
    rn = 1
  UNION ALL
  /* Elevator */
  SELECT
    id AS id_house,
    0 AS id_amenity,
    NULL AS id_user,
    NULL AS rev,
    1 AS rev_type,
    has_elevator AS has_feature,
    TRUE AS is_condo_amenity,
    COALESCE(ts_updated, NOW()) AS ts_change
  FROM datalake_ebdb_clean.house
), amenities_full_log AS (
  SELECT
    *
  FROM amenities_aud
  UNION ALL
  SELECT
    *
  FROM amenities_current
  UNION ALL
  SELECT
    *
  FROM condo_amenities_aud
  UNION ALL
  SELECT
    *
  FROM condo_amenities_current
),
-- Particularly in the first few years of operation, instead of updating existing rows, we would delete every single
-- row and then create new ones after. Here, we're removing changes from the aud that are replaced by another change in less than a minute
removed_redundancies AS (
  SELECT
    id_house,
    id_user,
    id_amenity,
    rev,
    rev_type,
    has_feature,
    is_condo_amenity,
    ts_change
  FROM (
    SELECT
      id_house,
      id_user,
      id_amenity,
      rev,
      rev_type,
      has_feature,
      is_condo_amenity,
      ts_change,
      -- rev is appended as a final tie-break: ts_change/rev_type alone can tie when several
      -- audit revisions land in the same second (see delete+recreate note above), and rev
      -- (unique, monotonically-assigned revision id) makes the window order fully deterministic
      -- across engines instead of depending on physical row/shuffle order.
      LEAD(has_feature) OVER (
        PARTITION BY id_house, NOT rev IS NULL, id_amenity, is_condo_amenity
        ORDER BY ts_change, rev_type DESC, rev
      ) AS next_has_feature,
      -- rev_type = 2 (deletion) will come first, so its row would be removed if the deletion is simultaneous with an insert
      LEAD(ts_change) OVER (
        PARTITION BY id_house, NOT rev IS NULL, id_amenity, is_condo_amenity
        ORDER BY ts_change, rev_type DESC, rev
      ) AS next_ts_change
    FROM amenities_full_log
  ) AS ranked_redundancies
  WHERE
    COALESCE(UNIX_TIMESTAMP(next_ts_change) - UNIX_TIMESTAMP(ts_change), 61) > 60
    OR has_feature IS NOT DISTINCT FROM next_has_feature
), deduped_amenities AS (
  SELECT
    id_house,
    id_user,
    id_amenity,
    rev,
    rev_type,
    has_feature,
    is_condo_amenity,
    ts_change
  FROM (
    SELECT
      id_house,
      id_user,
      id_amenity,
      rev,
      rev_type,
      has_feature,
      is_condo_amenity,
      ts_change,
      LAG(has_feature) OVER (
        PARTITION BY id_house, id_amenity, is_condo_amenity
        ORDER BY rev NULLS LAST, rev_type DESC
      ) AS prev_has_feature
    FROM removed_redundancies
  ) AS ranked_dedup
  WHERE
    prev_has_feature IS DISTINCT FROM has_feature
)
SELECT
  da.id_house,
  da.id_user,
  da.id_amenity,
  da.rev,
  da.rev_type,
  da.has_feature,
  da.is_condo_amenity,
  CASE WHEN NOT da.rev IS NULL OR ur.id_user = 293046 THEN TRUE ELSE FALSE END AS is_atlas_update,
  da.ts_change,
  LEAD(da.ts_change) OVER (PARTITION BY da.id_house, da.id_amenity, da.is_condo_amenity ORDER BY da.rev NULLS LAST, da.rev_type DESC) AS ts_next_change
FROM deduped_amenities AS da
LEFT JOIN datalake_ebdb_clean.user_revision_entity AS ur
  ON da.rev = ur.id
