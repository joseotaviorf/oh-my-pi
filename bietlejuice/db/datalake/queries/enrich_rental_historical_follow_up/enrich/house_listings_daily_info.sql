WITH daily_base AS (
    SELECT
        date AS dt_day,
        month_start AS dt_month_started,
        month_end AS dt_month_ended,
        week_start AS dt_week_started,
        week_end AS dt_week_ended,
        year,
        month,
        day
    FROM
        datalake_quintoandar.aux_date
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
),
lbc AS (
    SELECT
        id_house,
        CAST(MAX(CAST((business_context = 'SALE') AS INTEGER)) AS BOOLEAN) AS is_for_sale,
        CAST(MAX(CAST((business_context = 'RENT') AS INTEGER)) AS BOOLEAN) AS is_for_rent
    FROM 
        datalake_ebdb_listing.listing_business_context
    GROUP BY 1
),
last_ciq_of_day AS (
    /*
    One house can have multiples agencies assigned in the same day, so we could not guarantee
    one status per day. To do so, we are assuming that only the last status/agency
    of this house in a day will be considered. We aligned with SWE
    and the rule is programs are excludent, so there is only
    one program:house per time. 
    For the SELECT program, we are not sure yet, but for CIQ/ASP this is valid.
    
    In addition, there are periods around June - 2021 (In our auds) when two programs exists at
    the same time. It's an error, and we are treating it in this CTE.
    
    */
    SELECT /*+ RANGE_JOIN(hch, 340) */
        id_house,
        consultant_type,
        MAX(rev) OVER(PARTITION BY id_house, dbase.dt_day) = rev AS is_last_status_house_of_day,
        dbase.dt_day,
        ts_enrollment_started,
        ts_enrollment_ended
    FROM
        datalake_big_agent.house_consultant_history AS hch
    JOIN
        daily_base AS dbase
            ON dbase.dt_day >= DATE(hch.ts_enrollment_started)
            AND dbase.dt_day < COALESCE(DATE(hch.ts_enrollment_ended), '2100-01-01')
    WHERE
        hch.is_last_status_of_day = True
)
SELECT /*+ RANGE_JOIN(heh, 1180) */
    CONCAT(hl.id_house_listing, DATE_FORMAT(dbase.dt_day, 'yMMdd')) AS id_house_listing_day,
    hl.id_house_listing,
    hl.id_house,
    h.id_country,
    hl.id_contract,
    heh.id_occupant,
    h.id_region,
    lcod.consultant_type,
    heh.doorman_type,
    awk.first_key_location,
    hls.status_history,
    hls.status_change_reason,
    hl.listing_category,
    hl.is_exclusive,
    CASE
        WHEN lbc.id_house IS NULL THEN TRUE -- When house is not in listing_business_context, it is for rent
        ELSE COALESCE(lbc.is_for_rent, FALSE)
    END AS is_for_rent,
    COALESCE(lbc.is_for_sale, FALSE) AS is_for_sale,
    IF(dbase.dt_month_started = dbase.dt_day, TRUE, FALSE) AS is_month_start,
    IF(dbase.dt_month_ended = dbase.dt_day, TRUE, FALSE) AS is_month_end,
    IF(dbase.dt_week_started = dbase.dt_day, TRUE, FALSE) AS is_week_start,
    IF(dbase.dt_week_ended = dbase.dt_day, TRUE, FALSE) AS is_week_end,
    dbase.dt_day,
    hls.ts_status_started,
    hls.ts_status_ended,
    dbase.year,
    dbase.month,
    dbase.day
FROM
    datalake_ebdb_listing.house_listing AS hl -- id_house_listing is PK
JOIN
    datalake_ebdb_listing.house_listing_status AS hls -- 1:M => 1 listing has M statuses 
        ON hl.id_house_listing = hls.id_house_listing
        AND hls.is_last_status_of_day = True
JOIN
    daily_base AS dbase
        ON ((dbase.dt_day >= DATE(hls.ts_status_started)
              AND dbase.dt_day < COALESCE(DATE(hls.ts_status_ended), '2100-01-01'))
              OR (dbase.dt_day = DATE(hls.ts_status_started)
                  AND dbase.dt_day = DATE(hls.ts_status_ended))
             )
LEFT JOIN
    lbc
        ON lbc.id_house = hl.id_house
LEFT JOIN
    datalake_ebdb_listing.house AS h
        ON hl.id_house = h.id
LEFT JOIN
    last_ciq_of_day AS lcod
        ON hl.id_house = lcod.id_house
        AND dbase.dt_day = lcod.dt_day
        AND lcod.is_last_status_house_of_day = True
LEFT JOIN
    datalake_ebdb_listing.house_entrance_history AS heh
        ON hl.id_house = heh.id_house
        AND dbase.dt_day >= DATE(heh.ts_entrance_started)
        AND dbase.dt_day < COALESCE(DATE(heh.ts_entrance_ended), '2100-01-01')
        AND heh.is_last_status_of_day = True
LEFT JOIN
    datalake_ebdb_listing.agents_with_keys AS awk
        ON hl.id_house_listing = awk.id_house_listing
/* 
   This table is used for For_Rent and
   should be similar to fact_house_listing_status, so
   we are removing houses that are pure Sales from here.
*/
WHERE
    lbc.id_house IS NULL
    OR lbc.is_for_rent