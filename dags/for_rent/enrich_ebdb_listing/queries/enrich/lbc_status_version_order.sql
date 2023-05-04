WITH 
house AS (
  SELECT 
    house.id_house,
    house.status_history AS status,
    house.reason AS status_reason,
    house.ts_status_changed AS ts_state_started,
    house.ts_status_changed_next AS ts_state_ended,
    house.order_version AS listing_version,
    house.order_status AS state_order,
    house.events_change_status,
    IF((house.events_change_status IS NOT NULL OR house.ts_status_changed = house.ts_first_publication), 1, 0) AS trigger_new_version,
    MAX(house.order_status) OVER(PARTITION BY house.id_house) AS max_house_state_order,
    house.country_code,
    house.ts_first_publication,
    house.rev,
    MAX(rev.reason) OVER(PARTITION BY house.id_house, house.status_history, house.ts_status_changed) AS revision_reason
  FROM 
    datalake_ebdb_listing.house_status_version_order AS house
  LEFT JOIN
    datalake_ebdb_clean.user_revision_entity AS rev
      ON rev.id = house.rev
  WHERE
    ts_status_changed < '2020-01-06 19:04:25' --Timestamp when table listing_business_context was created
),
last_house_state AS (
  SELECT 
    h.id_house,
    h.status,
    h.status_reason,
    h.ts_state_started,
    h.ts_state_ended,
    DATEDIFF(h.ts_state_ended, h.ts_state_started) AS days_in_state,
    DATEDIFF(h.ts_state_ended, h.ts_state_started) AS days_in_status,
    IF(h.state_order=1, TRUE, FALSE) AS is_first_status,
    IF(events_change_status IS NOT NULL, 1, 0) AS trigger_new_version,
    h.listing_version,
    h.state_order,
    h.max_house_state_order,
    h.country_code,
    h.ts_first_publication
  FROM
    house AS h
  WHERE 
    state_order = max_house_state_order
),
first_publication AS (
  SELECT
    id_house,
    MIN(ts_state_started) AS ts_first_publication
  FROM
    datalake_ebdb_listing.business_context_history
  WHERE
    status = 'PUBLISHED'
  GROUP BY
    id_house
),
business_context_history AS (
  SELECT 
      bch.id_house,
      bch.country_code,
      bch.business_context,
      LAG(bch.status) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started) AS previous_state_status,
      LAG(bch.status_reason) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started) AS previous_status_reason,
      LAG(bch.suspension_reason) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started) AS previous_suspension_reason,
      LAG(
          CAST((CAST(CAST(COALESCE(bch.ts_state_ended, NOW()) AS TIMESTAMP) AS LONG) - CAST(CAST(bch.ts_state_started AS TIMESTAMP) AS LONG))/(86400) AS INTEGER)
      ) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started) AS days_in_previous_state,
      bch.status,
      bch.status_reason,
      bch.suspension_reason,
      CAST((CAST(CAST(COALESCE(bch.ts_state_ended, NOW()) AS TIMESTAMP) AS LONG) - CAST(CAST(bch.ts_state_started AS TIMESTAMP) AS LONG))/(86400) AS INTEGER) AS days_in_state, 
      IF(
        bch.status = LAG(bch.status) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started),
        LAG(
            CAST((CAST(CAST(COALESCE(bch.ts_state_ended, NOW()) AS TIMESTAMP) AS LONG) - CAST(CAST(bch.ts_state_started AS TIMESTAMP) AS LONG))/(86400) AS INTEGER)
        ) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started) 
        +
        CAST((CAST(CAST(COALESCE(bch.ts_state_ended, NOW()) AS TIMESTAMP) AS LONG) - CAST(CAST(bch.ts_state_started AS TIMESTAMP) AS LONG))/(86400) AS INTEGER),
        CAST((CAST(CAST(COALESCE(bch.ts_state_ended, NOW()) AS TIMESTAMP) AS LONG) - CAST(CAST(bch.ts_state_started AS TIMESTAMP) AS LONG))/(86400) AS INTEGER)
      ) AS days_in_status,
      LEAD(bch.status) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started) AS next_status,
      LEAD(bch.ts_state_started) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started) AS ts_next_status_change,
      LEAD(bch.status_reason) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started) AS next_status_reason,
      LEAD(bch.suspension_reason) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started) AS next_suspension_reason,
      LEAD(
          CAST((CAST(CAST(COALESCE(bch.ts_state_ended, NOW()) AS TIMESTAMP) AS LONG) - CAST(CAST(bch.ts_state_started AS TIMESTAMP) AS LONG))/(86400) AS INTEGER)
      ) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started) AS days_in_next_state,
      bch.ts_state_started,
      bch.ts_state_ended,
      IF(
        LAG(bch.status) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started) IS NULL
        , TRUE
        , FALSE
      ) AS is_first_status,
      LAG(IF(
        LAG(bch.status) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started) IS NULL
        , TRUE
        , FALSE
        )
      ) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started) AS is_previous_first_status,
      ROW_NUMBER() OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started ASC) AS lbc_state_order,
      IF(
        lhs.state_order IS NOT NULL
        , lhs.state_order + ROW_NUMBER() OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started ASC)
        , ROW_NUMBER() OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started ASC)
      ) AS state_order,
      MAX(bch.rev) OVER(PARTITION BY bch.id_house, bch.status, bch.ts_state_started) AS rev,
      MAX(rev.reason) OVER(PARTITION BY bch.id_house, bch.status, bch.ts_state_started) AS revision_reason,
      COALESCE(lhs.ts_first_publication, fp.ts_first_publication) AS ts_first_publication
  FROM 
      datalake_ebdb_listing.business_context_history AS bch
  LEFT JOIN 
    last_house_state AS lhs
      ON lhs.id_house = bch.id_house
  LEFT JOIN
    datalake_ebdb_clean.user_revision_entity AS rev
      ON rev.id = bch.rev
  LEFT JOIN
    first_publication AS fp
      ON fp.id_house = bch.id_house
  WHERE
      bch.business_context = 'RENT'
), 
status_change_time AS (
  SELECT 
    bch.id_house, 
    bch.country_code,
    bch.status,
    IF(
      bch.status <> bch.previous_state_status 
      OR bch.previous_state_status IS NULL
      , bch.ts_state_started
      , NULL
    ) AS start_time,
    IF(bch.status <> bch.next_status, bch.ts_state_ended, NULL) AS end_time,
    bch.ts_state_started,
    bch.ts_state_ended,
    bch.lbc_state_order
  FROM 
    business_context_history AS bch
  WHERE
    (bch.status <> bch.previous_state_status 
      OR bch.previous_state_status IS NULL)
    OR
    (bch.status <> bch.next_status)
), 
status_change AS (
  SELECT DISTINCT
    sct.id_house,
    sct.country_code,
    sct.status,
    COALESCE(
        sct.start_time, 
        LAG(sct.start_time) OVER(PARTITION BY sct.id_house ORDER BY sct.ts_state_started)
    ) AS ts_status_started,
    COALESCE(
        sct.end_time, 
        LEAD(sct.end_time) OVER(PARTITION BY sct.id_house ORDER BY sct.ts_state_started)
    ) AS ts_status_ended
  FROM 
    status_change_time AS sct
), 
status_order AS (
  SELECT 
    sc.id_house,
    sc.country_code,
    LAG(sc.status) OVER(PARTITION BY sc.id_house ORDER BY sc.ts_status_started) AS prev_status,
    sc.status,
    LEAD(sc.status) OVER(PARTITION BY sc.id_house ORDER BY sc.ts_status_started) AS next_status,
    sc.ts_status_started,
    sc.ts_status_ended,
    CAST((CAST(CAST(COALESCE(sc.ts_status_ended, now()) AS TIMESTAMP) AS LONG) - CAST(CAST(sc.ts_status_started AS TIMESTAMP) AS LONG))/(86400) AS INTEGER) AS days_in_status
  FROM 
    status_change AS sc
),
trigger AS (
  SELECT
    bch.id_house,
    bch.country_code,
    so.prev_status,
    bch.status,
    so.next_status,
    bch.status_reason,
    bch.ts_state_started,
    so.days_in_status,
    IF(
        (
          bch.lbc_state_order = 1
          AND
          lhs.id_house IS NOT NULL
          AND
          (
            (-- First Listing
              (--There is no publication event previous to LBC
                lhs.ts_first_publication IS NULL
                OR
                lhs.ts_first_publication >= '2020-01-06 19:04:25'
              )
              AND
              (
                  bch.status = 'EDITING'
                  AND bch.next_status = 'PUBLISHED'
              )
              OR
              bch.status = 'PUBLISHED'
            )
            OR
            ( --Recovered
              bch.next_status = 'PUBLISHED' 
              AND bch.status = 'UNPUBLISHED' 
              AND IF(lhs.status = 'despublicado', lhs.days_in_status + so.days_in_status, so.days_in_status) >= 84
            )
            OR
            ( --Relisting
                bch.next_status = 'PUBLISHED'
                AND ( --Remove available_soon cases
                        bch.next_status_reason <> 'RELISTING' 
                        OR bch.next_status_reason IS NULL
                    )
                AND bch.status = 'SUSPENDED'
                AND bch.status_reason = 'RENTED'
                AND lhs.status <> 'alugado'
            )
            OR
            ( --Relisting
                bch.status = 'UNPUBLISHED'
                AND so.next_status = 'PUBLISHED'
                AND lhs.status = 'alugado'
            )
          )
        )
        OR
        (
          (
            bch.lbc_state_order > 1
            OR
            lhs.id_house IS NULL
          )
          AND
          ( --First Listing
              (
                lhs.ts_first_publication IS NULL 
                OR 
                lhs.ts_first_publication >= '2020-01-06 19:04:25'
              )
              AND
              (
                (
                    bch.status = 'EDITING'
                    AND bch.lbc_state_order = 1
                    AND bch.next_status = 'PUBLISHED'
                )
                OR
                (
                    bch.status = 'PUBLISHED'
                    AND lhs.id_house IS NULL
                    AND bch.previous_state_status IS NULL
                )
                OR
                (
                    bch.next_status = 'PUBLISHED'
                    AND CAST(lhs.ts_first_publication AS TIMESTAMP) = CAST(bch.ts_next_status_change AS TIMESTAMP)
                )
                OR
                (
                  so.prev_status = 'EDITING'
                  AND bch.is_previous_first_status IS TRUE
                  AND bch.next_status = 'PUBLISHED'
                )
              )
          )
          OR 
          ( --Recovered
              bch.next_status = 'PUBLISHED' 
              AND bch.status = 'UNPUBLISHED' 
              AND so.days_in_status >= 84
          )
          OR
          ( --Relisting
              bch.next_status = 'PUBLISHED'
              AND ( --Remove available_soon cases
                      bch.next_status_reason <> 'RELISTING' 
                      OR bch.next_status_reason IS NULL
                  )
              AND bch.status = 'SUSPENDED'
              AND bch.status_reason = 'RENTED'
          )
          OR
          ( --Relisting
              bch.status = 'UNPUBLISHED'
              AND so.next_status = 'PUBLISHED'
              AND bch.previous_state_status = 'SUSPENDED'
              AND bch.previous_status_reason = 'RENTED'
          )
          OR --Early demand
          (
              bch.next_status = 'PUBLISHED'
              AND bch.next_status_reason LIKE 'RELISTING_%'
          )
        ),
        1,
        0
    ) AS trigger_new_version
  FROM
    business_context_history AS bch
  LEFT JOIN
    status_order AS so
      ON so.id_house = bch.id_house 
        AND so.country_code = bch.country_code
        AND so.status = bch.status
        AND (bch.ts_state_started >= so.ts_status_started
            AND bch.ts_state_ended <= so.ts_status_ended)
  LEFT JOIN 
    last_house_state AS lhs
      ON lhs.id_house = bch.id_house
  
), merge_version AS (
  SELECT 
    id_house,
    country_code,
    status,
    status_reason,
    ts_state_started,
    ts_state_ended,
    DATEDIFF(ts_state_ended, ts_state_started)  AS days_in_state,
    DATEDIFF(ts_state_ended, ts_state_started)  AS days_in_status,
    IF(LAG(status) OVER(PARTITION BY id_house ORDER BY ts_state_started) IS NULL, TRUE, FALSE) AS is_first_status,
    trigger_new_version,
    listing_version,
    state_order,
    max_house_state_order AS max_state_order,
    rev,
    revision_reason,
    ts_first_publication
  FROM 
    house

  UNION ALL

  SELECT 
      bch.id_house,
      bch.country_code,
      bch.status,
      bch.status_reason,
      bch.ts_state_started,
      bch.ts_state_ended,
      bch.days_in_state, 
      t.days_in_status,
      IF(bch.previous_state_status IS NULL, TRUE, FALSE) AS is_first_status,
      t.trigger_new_version,
      COALESCE(
          COALESCE(lhs.listing_version, 0)
          + 
          SUM(
              t.trigger_new_version
          ) OVER (PARTITION BY bch.id_house ORDER BY bch.ts_state_started ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)
          , IF(bch.state_order = 1 AND bch.status = 'PUBLISHED', COALESCE(lhs.listing_version, 0) + 1, COALESCE(lhs.listing_version, 0) + 0)
          , 0
      ) AS listing_version,
      bch.state_order,
      MAX(bch.state_order) OVER(PARTITION BY bch.id_house) AS max_state_order,
      bch.rev,
      bch.revision_reason,
      bch.ts_first_publication
  FROM
    business_context_history AS bch
  LEFT JOIN 
    trigger AS t
      ON t.id_house = bch.id_house
        AND t.country_code = bch.country_code
        AND t.status = bch.status
        AND COALESCE(t.status_reason, '') = COALESCE(bch.status_reason, '')
        AND t.ts_state_started = bch.ts_state_started
  LEFT JOIN 
    last_house_state AS lhs
      ON lhs.id_house = bch.id_house
)
SELECT 
  id_house,
  country_code,
  status,
  status_reason,
  rev,
  revision_reason,
  ts_first_publication,
  ts_state_started,
  ts_state_ended,
  days_in_state,
  days_in_status,
  trigger_new_version,
  listing_version,
  state_order,
  MAX(max_state_order) OVER(PARTITION BY id_house) AS max_state_order
FROM 
  merge_version