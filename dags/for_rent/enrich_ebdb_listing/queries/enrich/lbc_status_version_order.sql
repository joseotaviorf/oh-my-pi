WITH 
first_lbc_state AS (
  SELECT 
    bch.id_house,
    bch.status,
    bch.status_reason,
    bch.ts_state_started,
    bch.ts_state_ended,
    DATEDIFF(bch.ts_state_ended, bch.ts_state_started) AS days_in_state,
    DATEDIFF(bch.ts_state_ended, bch.ts_state_started) AS days_in_status,
    bch.country_code
  FROM
    datalake_ebdb_listing.business_context_history AS bch
  WHERE 
    bch.business_context = 'RENT'
  QUALIFY 
    ROW_NUMBER() OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started ASC, bch.ts_state_ended ASC) = 1   
),
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
    IF(
        (
          house.events_change_status IS NOT NULL 
          OR house.ts_status_changed_next = house.ts_first_publication 
          OR (
              (house.order_version = 0 OR house.order_status=1)
              AND 
              LEAD(house.status_history) OVER(PARTITION BY house.id_house ORDER BY house.ts_status_changed, house.ts_status_changed_next) = 'publicado'
          )
          OR (
            house.order_status=1 
            AND 
            house.order_version=1
          )
        ), 
        1, 
        0
      ) AS trigger_new_version,
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
    CAST(FROM_UNIXTIME(CAST(ts_revision AS BIGINT)/1000) AS TIMESTAMP) < '2020-01-06 19:04:25' --Timestamp when table listing_business_context was created
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
    IF(
      (
        (h.status = 'alugado' AND flbc.status = 'SUSPENDED' AND flbc.status_reason = 'RENTED')
        OR
        (h.status = 'despublicado' AND h.trigger_new_version=1 AND flbc.status = 'UNPUBLISHED')
      )
      , 0
      , h.trigger_new_version
    ) AS trigger_new_version,
    h.listing_version,
    h.state_order,
    h.max_house_state_order,
    h.country_code,
    h.ts_first_publication,
    flbc.status AS lbc_first_status,
    flbc.status_reason AS lbc_first_status_reason
  FROM
    house AS h
  LEFT JOIN first_lbc_state AS flbc
    ON flbc.id_house = h.id_house
  WHERE 
    h.state_order = h.max_house_state_order
),
first_publication AS (
  SELECT
    id_house,
    MIN(ts_state_started) AS ts_first_publication
  FROM
    datalake_ebdb_listing.business_context_history
  WHERE
    status = 'PUBLISHED'
    AND business_context = 'RENT'
  GROUP BY
    id_house
),
business_context_history AS (
  SELECT 
      bch.id_house,
      bch.country_code,
      bch.business_context,
      LAG(bch.status) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started, COALESCE(bch.ts_state_ended, (CURRENT_TIMESTAMP - INTERVAL 1 DAY))) AS previous_state_status,
      LAG(bch.status_reason) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started, COALESCE(bch.ts_state_ended, (CURRENT_TIMESTAMP - INTERVAL 1 DAY))) AS previous_status_reason,
      LAG(bch.status_reason, 2) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started, COALESCE(bch.ts_state_ended, (CURRENT_TIMESTAMP - INTERVAL 1 DAY))) AS previous_to_previous_status_reason,
      LAG(bch.suspension_reason) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started, COALESCE(bch.ts_state_ended, (CURRENT_TIMESTAMP - INTERVAL 1 DAY))) AS previous_suspension_reason,
      LAG(
          CAST((CAST(CAST(COALESCE(bch.ts_state_ended, NOW()) AS TIMESTAMP) AS LONG) - CAST(CAST(bch.ts_state_started AS TIMESTAMP) AS LONG))/(86400) AS INTEGER)
      ) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started, COALESCE(bch.ts_state_ended, (CURRENT_TIMESTAMP - INTERVAL 1 DAY))) AS days_in_previous_state,
      bch.status,
      bch.status_reason,
      bch.suspension_reason,
      CAST((CAST(CAST(COALESCE(bch.ts_state_ended, NOW()) AS TIMESTAMP) AS LONG) - CAST(CAST(bch.ts_state_started AS TIMESTAMP) AS LONG))/(86400) AS INTEGER) AS days_in_state, 
      IF(
        bch.status = LAG(bch.status) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started, COALESCE(bch.ts_state_ended, (CURRENT_TIMESTAMP - INTERVAL 1 DAY))),
        LAG(
            CAST((CAST(CAST(COALESCE(bch.ts_state_ended, NOW()) AS TIMESTAMP) AS LONG) - CAST(CAST(bch.ts_state_started AS TIMESTAMP) AS LONG))/(86400) AS INTEGER)
        ) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started, COALESCE(bch.ts_state_ended, (CURRENT_TIMESTAMP - INTERVAL 1 DAY))) 
        +
        CAST((CAST(CAST(COALESCE(bch.ts_state_ended, NOW()) AS TIMESTAMP) AS LONG) - CAST(CAST(bch.ts_state_started AS TIMESTAMP) AS LONG))/(86400) AS INTEGER),
        CAST((CAST(CAST(COALESCE(bch.ts_state_ended, NOW()) AS TIMESTAMP) AS LONG) - CAST(CAST(bch.ts_state_started AS TIMESTAMP) AS LONG))/(86400) AS INTEGER)
      ) AS days_in_status,
      LEAD(bch.status) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started, COALESCE(bch.ts_state_ended, (CURRENT_TIMESTAMP - INTERVAL 1 DAY))) AS next_status,
      LEAD(bch.ts_state_started) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started, COALESCE(bch.ts_state_ended, (CURRENT_TIMESTAMP - INTERVAL 1 DAY))) AS ts_next_status_change,
      LEAD(bch.status_reason) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started, COALESCE(bch.ts_state_ended, (CURRENT_TIMESTAMP - INTERVAL 1 DAY))) AS next_status_reason,
      LEAD(bch.suspension_reason) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started, COALESCE(bch.ts_state_ended, (CURRENT_TIMESTAMP - INTERVAL 1 DAY))) AS next_suspension_reason,
      LEAD(
          CAST((CAST(CAST(COALESCE(bch.ts_state_ended, NOW()) AS TIMESTAMP) AS LONG) - CAST(CAST(bch.ts_state_started AS TIMESTAMP) AS LONG))/(86400) AS INTEGER)
      ) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started, COALESCE(bch.ts_state_ended, (CURRENT_TIMESTAMP - INTERVAL 1 DAY))) AS days_in_next_state,
      bch.ts_state_started,
      bch.ts_state_ended,
      IF(
        LAG(bch.status) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started, COALESCE(bch.ts_state_ended, (CURRENT_TIMESTAMP - INTERVAL 1 DAY))) IS NULL
        , TRUE
        , FALSE
      ) AS is_first_status,
      LAG(IF(
        LAG(bch.status) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started, COALESCE(bch.ts_state_ended, (CURRENT_TIMESTAMP - INTERVAL 1 DAY))) IS NULL
        , TRUE
        , FALSE
        )
      ) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started, COALESCE(bch.ts_state_ended, (CURRENT_TIMESTAMP - INTERVAL 1 DAY))) AS is_previous_first_status,
      ROW_NUMBER() OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started ASC, COALESCE(bch.ts_state_ended, (CURRENT_TIMESTAMP - INTERVAL 1 DAY))) AS lbc_state_order,
      IF(
        lhs.state_order IS NOT NULL
        , lhs.state_order + ROW_NUMBER() OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started ASC, COALESCE(bch.ts_state_ended, (CURRENT_TIMESTAMP - INTERVAL 1 DAY)))
        , ROW_NUMBER() OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started ASC, COALESCE(bch.ts_state_ended, (CURRENT_TIMESTAMP - INTERVAL 1 DAY)))
      ) AS state_order,
      MAX(bch.rev) OVER(PARTITION BY bch.id_house, bch.status, bch.ts_state_started, COALESCE(bch.ts_state_ended, (CURRENT_TIMESTAMP - INTERVAL 1 DAY))) AS rev,
      MAX(rev.reason) OVER(PARTITION BY bch.id_house, bch.status, bch.ts_state_started, COALESCE(bch.ts_state_ended, (CURRENT_TIMESTAMP - INTERVAL 1 DAY))) AS revision_reason,
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
        LAG(sct.start_time) OVER(PARTITION BY sct.id_house ORDER BY sct.ts_state_started, COALESCE(sct.ts_state_ended, (CURRENT_TIMESTAMP - INTERVAL 1 DAY)))
    ) AS ts_status_started,
    COALESCE(
        sct.end_time, 
        LEAD(sct.end_time) OVER(PARTITION BY sct.id_house ORDER BY sct.ts_state_started, COALESCE(sct.ts_state_ended, (CURRENT_TIMESTAMP - INTERVAL 1 DAY)))
    ) AS ts_status_ended
  FROM 
    status_change_time AS sct
), 
status_order AS (
  SELECT 
    sc.id_house,
    sc.country_code,
    LAG(sc.status) OVER(PARTITION BY sc.id_house ORDER BY sc.ts_status_started, COALESCE(sc.ts_status_ended, (CURRENT_TIMESTAMP - INTERVAL 1 DAY))) AS prev_status,
    sc.status,
    LEAD(sc.status) OVER(PARTITION BY sc.id_house ORDER BY sc.ts_status_started, COALESCE(sc.ts_status_ended, (CURRENT_TIMESTAMP - INTERVAL 1 DAY))) AS next_status,
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
          lhs.trigger_new_version = 0
          AND
          (
            (-- First Listing
              (--There is no publication event previous to LBC
                bch.ts_first_publication IS NULL
                OR
                bch.ts_first_publication >= '2020-01-06 19:04:25'
              )
              AND
              (
                (
                  bch.status <> 'PUBLISHED'
                  AND bch.next_status = 'PUBLISHED'
                )
                OR
                (
                  bch.status = 'PUBLISHED'
                  AND lhs.status <> 'edicao'
                )
              )
            )
            OR
            ( --Recovered
              bch.next_status = 'PUBLISHED' 
              AND bch.status = 'UNPUBLISHED' 
              AND IF(lhs.status = 'despublicado' AND lhs.ts_first_publication IS NOT NULL, lhs.days_in_status + so.days_in_status, so.days_in_status) >= 84
              AND bch.ts_first_publication IS NOT NULL
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
          (
            ( --First Listing
                (
                  bch.ts_first_publication IS NULL 
                  OR 
                  bch.ts_first_publication >= '2020-01-06 19:04:25'
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
                    so.prev_status = 'EDITING'
                    AND bch.is_previous_first_status IS TRUE
                    AND bch.next_status = 'PUBLISHED'
                    AND bch.status <> 'PUBLISHED'
                  )
                  OR
                  (
                    bch.next_status = 'PUBLISHED'
                    AND bch.ts_first_publication = bch.ts_next_status_change
                  )
                )
            )
            OR 
            ( --Recovered
                bch.next_status = 'PUBLISHED' 
                AND bch.status = 'UNPUBLISHED' 
                AND so.days_in_status >= 84
                AND bch.ts_first_publication IS NOT NULL
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
                AND (
                  bch.status = 'SUSPENDED' 
                  AND 
                  bch.status_reason = 'RENTED'
                )
            )
            OR --Early demand
            ( --This covers the new scenario where the admin suspends the listing before publishing it as early demand
                bch.next_status = 'PUBLISHED'
                AND bch.next_status_reason LIKE 'RELISTING_%'
                AND (
                  bch.status = 'SUSPENDED'
                  AND 
                  bch.status_reason = 'Admin'
                  AND
                  (bch.previous_status_reason = 'RENTED' OR bch.previous_to_previous_status_reason = 'RENTED')
                )
            )
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
    h.id_house,
    h.country_code,
    h.status,
    h.status_reason,
    h.ts_state_started,
    IF(h.state_order = lhs.state_order, COALESCE(fls.ts_state_started, h.ts_state_ended), h.ts_state_ended) AS ts_state_ended,
    DATEDIFF(h.ts_state_ended, h.ts_state_started)  AS days_in_state,
    DATEDIFF(h.ts_state_ended, h.ts_state_started)  AS days_in_status,
    IF(LAG(h.status) OVER(PARTITION BY h.id_house ORDER BY h.ts_state_started, COALESCE(h.ts_state_ended,(CURRENT_TIMESTAMP - INTERVAL 1 DAY))) IS NULL, TRUE, FALSE) AS is_first_status,
    IF(h.state_order = h.max_house_state_order, lhs.trigger_new_version, 0) AS trigger_new_version,
    h.listing_version,
    NULL AS lbc_state_order,
    h.state_order,
    h.max_house_state_order AS max_state_order,
    h.rev,
    h.revision_reason,
    h.ts_first_publication
  FROM 
    house AS h
  JOIN last_house_state AS lhs
    ON lhs.id_house = h.id_house
  LEFT JOIN first_lbc_state AS fls
    ON fls.id_house = h.id_house

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
    NULL AS listing_version,
    bch.lbc_state_order,
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
), versioning AS (
  SELECT 
      m.id_house,
      m.country_code,
      m.status,
      m.status_reason,
      LAG(m.status_reason) OVER(PARTITION BY m.id_house ORDER BY m.ts_state_started, COALESCE(m.ts_state_ended, (CURRENT_TIMESTAMP - INTERVAL 1 DAY))) AS previous_status_reason,
      m.rev,
      m.revision_reason,
      IF(
          COALESCE( 
            m.listing_version,
            COALESCE(
              COALESCE(lhs.listing_version, 0)
              +
              SUM(
                  m.trigger_new_version
              ) OVER (PARTITION BY m.id_house ORDER BY m.ts_state_started, COALESCE(m.ts_state_ended,(CURRENT_TIMESTAMP - INTERVAL 1 DAY)) ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)
              , IF(
                  m.lbc_state_order = 1 
                  AND m.status = 'PUBLISHED' 
                  AND (lhs.trigger_new_version = 1 OR lhs.trigger_new_version IS NULL)
                  , COALESCE(lhs.listing_version, 0) + 1
                  , COALESCE(lhs.listing_version, 0) + 0
                ) 
              , 0
            )
          ) > 0
          , m.ts_first_publication
          , NULL
      ) AS ts_first_publication,
      CAST(m.ts_state_started AS TIMESTAMP) AS ts_state_started,
      CAST(m.ts_state_ended AS TIMESTAMP) AS ts_state_ended,
      MIN(m.ts_state_started) OVER (PARTITION BY m.id_house, m.listing_version) AS ts_listing_version_start,
      m.days_in_state,
      m.days_in_status,
      m.trigger_new_version,
      COALESCE( 
        m.listing_version,
        COALESCE(
          COALESCE(lhs.listing_version, 0)
          +
          SUM(
              m.trigger_new_version
          ) OVER (PARTITION BY m.id_house ORDER BY m.ts_state_started, COALESCE(m.ts_state_ended,(CURRENT_TIMESTAMP - INTERVAL 1 DAY)) ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)
          , IF(
              m.lbc_state_order = 1 
              AND m.status = 'PUBLISHED' 
              AND (lhs.trigger_new_version = 1 OR lhs.trigger_new_version IS NULL)
              , COALESCE(lhs.listing_version, 0) + 1
              , COALESCE(lhs.listing_version, 0) + 0
            )
          , 0
        )
      ) AS listing_version,
      m.lbc_state_order,
      m.state_order,
      MAX(m.max_state_order) OVER(PARTITION BY m.id_house) AS max_state_order,
      IF(
        MAX(m.state_order) OVER(
            PARTITION BY m.id_house, CAST(m.ts_state_started AS DATE)
        ) = m.state_order,
        TRUE,
        FALSE
      ) AS is_last_state_of_day
  FROM 
      merge_version AS m
  LEFT JOIN 
      last_house_state AS lhs
        ON lhs.id_house = m.id_house
),
early_demand_opt_out AS (
  SELECT DISTINCT
      v.id_house,
      v.listing_version
  FROM 
      versioning AS v
  WHERE
      v.revision_reason LIKE '[ED OPT-OUT]%'
)
SELECT
    v.id_house,
    v.country_code,
    v.status,
    v.status_reason,
    v.rev,
    v.revision_reason,
    v.ts_first_publication,
    v.ts_state_started,
    v.ts_state_ended,
    v.days_in_state,
    v.days_in_status,
    v.trigger_new_version,
    v.listing_version,
    IF(
      v.listing_version > 1
      AND
      (
        v.revision_reason LIKE '[TEMPORARY OPT-OUT RELISTING]%' --Manually removed from relisting by our Product Team
        OR
        (
          ed_opt_out.id_house IS NULL
          AND
          v.ts_listing_version_start >= TIMESTAMP('2024-05-16T15:42:20.000+00:00') --Timestamp of when the OPT-OUT policy started
          AND
          v.revision_reason LIKE '%TERMINATION_CANCELED%'
        )
        OR
        (
          v.ts_listing_version_start < TIMESTAMP('2024-05-16T15:42:20.000+00:00') --Timestamp of when the OPT-OUT policy started
          AND
          v.previous_status_reason LIKE 'RELISTING_%'
          AND
          v.revision_reason LIKE '%TERMINATION_CANCELED%'
        )
      )
      , TRUE
      , FALSE
    ) AS is_extended_rental,
    v.lbc_state_order,
    v.state_order,
    v.max_state_order,
    v.is_last_state_of_day
FROM 
    versioning AS v
LEFT JOIN
    early_demand_opt_out AS ed_opt_out
      ON ed_opt_out.id_house = v.id_house
        AND ed_opt_out.listing_version = v.listing_version