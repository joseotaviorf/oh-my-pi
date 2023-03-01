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
)
SELECT 
    id_house,
    country_code,
    status,
    status_reason,
    ts_state_started,
    ts_state_ended,
    days_in_state, 
    IF(previous_status IS NULL, TRUE, FALSE) AS is_first_status,
    IF(
        ( --First Listing
            (
                status = 'PUBLISHED'
                AND
                is_previous_first_status IS TRUE
            )
            OR
            (
                status = 'EDITING'
                AND
                next_status = 'PUBLISHED'
            )
            OR
            (
                status = 'PUBLISHED'
                AND
                previous_status IS NULL
            )
        )
        OR 
        ( --Recovered
            next_status = 'PUBLISHED' 
            AND status = 'UNPUBLISHED' 
            AND days_in_state >= 84
        )
        OR
        ( --Relisting
            next_status = 'PUBLISHED'
            AND (next_status_reason <> 'RELISTING' OR next_status_reason IS NULL) --Remove available_soon cases
            AND status = 'SUSPENDED'
            AND status_reason = 'RENTED'
        )
        OR
        ( --Relisting?
            status = 'UNPUBLISHED'
            AND next_status = 'PUBLISHED'
            AND previous_status = 'SUSPENDED'
            AND previous_status_reason = 'RENTED'
        )
        OR --Early demand
        (
            next_status = 'PUBLISHED'
            AND next_status_reason LIKE 'RELISTING_%'
        ),
        1,
        0
    ) AS trigger_new_version,
    COALESCE(
        SUM(
            IF(
                ( --First Listing
                    (
                        status = 'PUBLISHED'
                        AND
                        is_previous_first_status IS TRUE
                    )
                    OR
                    (
                        status = 'EDITING'
                        AND
                        next_status = 'PUBLISHED'
                    )
                    OR
                    (
                        status = 'PUBLISHED'
                        AND
                        previous_status IS NULL
                    )
                )
                OR 
                ( --Recovered
                    next_status = 'PUBLISHED' 
                    AND status = 'UNPUBLISHED' 
                    AND days_in_state >= 84
                )
                OR
                ( --Relisting
                    next_status = 'PUBLISHED'
                    AND (next_status_reason <> 'RELISTING' OR next_status_reason IS NULL) --Vitrine
                    AND status = 'SUSPENDED'
                    AND status_reason = 'RENTED'
                )
                OR
                ( --Relisting?
                    status = 'UNPUBLISHED'
                    AND next_status = 'PUBLISHED'
                    AND previous_status = 'SUSPENDED'
                    AND previous_status_reason = 'RENTED'
                )
                OR --Early demand
                (
                    next_status = 'PUBLISHED'
                    AND next_status_reason LIKE 'RELISTING_%'
                ),
                1,
                0
            )
        ) OVER (PARTITION BY id_house ORDER BY ts_state_started ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)
        , IF(previous_status IS NULL AND status = 'PUBLISHED', 1, 0)
        , 0
    ) AS listing_version,
    state_order,
    MAX(state_order) OVER(PARTITION BY id_house) AS max_state_order
FROM
    business_context_history