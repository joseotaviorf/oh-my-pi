WITH 
house_aud AS ( --Temporary remove data of houses published before the existence of the listing_business_context table to prevent hybrid versioning.
    SELECT
        DISTINCT id_house
    FROM 
        datalake_ebdb_clean.house_aud
    WHERE 
        YEAR(dt_first_publication) >= 2020

),
business_context_history AS (
    SELECT 
        bch.id_house,
        bch.country_code,
        bch.business_context,
        LAG(bch.status) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started) AS previous_status,
        LAG(bch.status_reason) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started) AS previous_status_reason,
        LAG(bch.suspension_reason) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started) AS previous_suspension_reason,
        LAG(
            CAST((CAST(CAST(COALESCE(bch.ts_state_ended, now()) AS TIMESTAMP) AS LONG) - CAST(CAST(bch.ts_state_started AS TIMESTAMP) AS LONG))/(86400) AS INTEGER)
        ) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started) AS days_in_previous_state,
        bch.status,
        bch.status_reason,
        bch.suspension_reason,
        CAST((CAST(CAST(COALESCE(bch.ts_state_ended, now()) AS TIMESTAMP) AS LONG) - CAST(CAST(bch.ts_state_started AS TIMESTAMP) AS LONG))/(86400) AS INTEGER) AS days_in_state, 
        IF(
          status = LAG(bch.status) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started),
          LAG(
              CAST((CAST(CAST(COALESCE(bch.ts_state_ended, now()) AS TIMESTAMP) AS LONG) - CAST(CAST(bch.ts_state_started AS TIMESTAMP) AS LONG))/(86400) AS INTEGER)
          ) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started) 
          +
          CAST((CAST(CAST(COALESCE(bch.ts_state_ended, now()) AS TIMESTAMP) AS LONG) - CAST(CAST(bch.ts_state_started AS TIMESTAMP) AS LONG))/(86400) AS INTEGER),
          CAST((CAST(CAST(COALESCE(bch.ts_state_ended, now()) AS TIMESTAMP) AS LONG) - CAST(CAST(bch.ts_state_started AS TIMESTAMP) AS LONG))/(86400) AS INTEGER)
        ) AS days_in_status,
        LEAD(bch.status) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started) AS next_status,
        LEAD(bch.status_reason) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started) AS next_status_reason,
        LEAD(bch.suspension_reason) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started) AS next_suspension_reason,
        LEAD(
            CAST((CAST(CAST(COALESCE(bch.ts_state_ended, now()) AS TIMESTAMP) AS LONG) - CAST(CAST(bch.ts_state_started AS TIMESTAMP) AS LONG))/(86400) AS INTEGER)
        ) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started) AS days_in_next_state,
        bch.ts_state_started,
        bch.ts_state_ended,
        LAG(IF(LAG(bch.status) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started) IS NULL, TRUE, FALSE)) OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started) AS is_previous_first_status,
        ROW_NUMBER() OVER(PARTITION BY bch.id_house ORDER BY bch.ts_state_started ASC) state_order
    FROM 
        datalake_ebdb_listing.business_context_history AS bch
    JOIN house_aud AS h_aud
        ON h_aud.id_house = bch.id_house
    WHERE
        bch.business_context = 'RENT'
),
trigger AS (
  SELECT
    id_house,
    country_code,
    status,
    status_reason,
    ts_state_started,
    IF(
        ( --First Listing
            (
                bch.status = 'PUBLISHED'
                AND
                bch.is_previous_first_status IS TRUE
                AND 
                bch.previous_status <> 'EDITING'
            )
            OR
            (
                bch.status = 'EDITING'
                AND
                bch.next_status = 'PUBLISHED'
            )
            OR
            (
                bch.status = 'PUBLISHED'
                AND
                bch.previous_status IS NULL
            )
            OR
            (
              bch.previous_status = 'EDITING'
              AND
              bch.status = 'UNPUBLISHED'
              AND
              bch.next_status = 'PUBLISHED'
            )
        )
        OR 
        ( --Recovered
            bch.next_status = 'PUBLISHED' 
            AND bch.status = 'UNPUBLISHED' 
            AND bch.days_in_status >= 84
        )
        OR
        ( --Relisting
            bch.next_status = 'PUBLISHED'
            AND (bch.next_status_reason <> 'RELISTING' OR bch.next_status_reason IS NULL) --Remove available_soon cases
            AND bch.status = 'SUSPENDED'
            AND bch.status_reason = 'RENTED'
        )
        OR
        ( --Relisting?
            bch.status = 'UNPUBLISHED'
            AND bch.next_status = 'PUBLISHED'
            AND bch.previous_status = 'SUSPENDED'
            AND bch.previous_status_reason = 'RENTED'
        )
        OR --Early demand
        (
            bch.next_status = 'PUBLISHED'
            AND bch.next_status_reason LIKE 'RELISTING_%'
        ),
        1,
        0
    ) AS trigger_new_version
  FROM
    business_context_history AS bch
)
SELECT 
    bch.id_house,
    bch.country_code,
    bch.status,
    bch.status_reason,
    bch.ts_state_started,
    bch.ts_state_ended,
    bch.days_in_state, 
    bch.days_in_status,
    IF(bch.previous_status IS NULL, TRUE, FALSE) AS is_first_status,
    t.trigger_new_version,
    COALESCE(
        SUM(
            t.trigger_new_version
        ) OVER (PARTITION BY bch.id_house ORDER BY bch.ts_state_started ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)
        , IF(bch.previous_status IS NULL AND bch.status = 'PUBLISHED', 1, 0)
        , 0
    ) AS listing_version,
    bch.state_order,
    MAX(bch.state_order) OVER(PARTITION BY bch.id_house) AS max_state_order
FROM
    business_context_history AS bch
LEFT JOIN 
  trigger AS t
  ON t.id_house = bch.id_house
    AND t.country_code = bch.country_code
    AND t.status = bch.status
    AND COALESCE(t.status_reason, '') = COALESCE(bch.status_reason, '')
    AND t.ts_state_started = bch.ts_state_started