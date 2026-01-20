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
    -- If a status ends in the current day, but the listing still existing and there's a new status
    -- we are not consuming the ended status in this day. In order to update the ts_status_ended
    -- for this status, we need to go back 1 day and rewrite its partition.
        date BETWEEN DATE('{year}-{month}-{day}') - INTERVAL 1 DAY AND DATE('{year}-{month}-{day}')
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
        id_partner,
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
),
rent_listing as (
    SELECT
        id_house,
        MAX(rental_administrator) AS rental_administrator
    FROM
        datalake_ebdb_listing.rent_listing
    GROUP BY 1
),
b2b AS (
    SELECT
        id_house,
        MAX(is_b2b) AS is_b2b
    FROM
        datalake_b2b.house_listing
    GROUP BY 1
),
previous_listing_early_demand AS (
  SELECT
    hl.id_house_listing,
    hl.id_house,
    hl.id_contract
  FROM
    datalake_ebdb_listing.house_listing AS hl
  JOIN
    datalake_ebdb_contract.contract AS c
      ON hl.id_contract = c.id
      AND c.status = 'Ativo'
  JOIN
    datalake_ebdb_listing.house_listing AS ed
      ON hl.id_house = ed.id_house
      AND hl.version = ed.version - 1
),
lpv AS (
    SELECT
        COUNT(*) AS listing_page_viewed,
        hl.id_house_listing,
        dbase.dt_day
    FROM
        datalake_amplitude_clean.170698_listing_page_viewed_events AS lpve
    JOIN
        daily_base AS dbase
            ON dbase.year = lpve.year
            AND dbase.month = lpve.month
            AND dbase.day = lpve.day
    JOIN
        datalake_ebdb_listing.house_listing AS hl
            ON hl.id_house = lpve.ep_house_id
            AND lpve.ts_event >= hl.ts_listing_version_start
            AND lpve.ts_event < COALESCE(hl.ts_listing_version_end, '2100-01-01')
    WHERE
        lpve.ep_house_id IS NOT NULL
        AND UPPER(lpve.business_context) = 'RENT'
    GROUP BY
        2, 3
),
srpv_explode AS (
    SELECT
        EXPLODE(srpv.ids_search_results_list) AS id_house,
        srpv.ts_event,
        dbase.dt_day
    FROM
        datalake_amplitude_clean.170698_search_results_page_viewed_events AS srpv
    JOIN
        daily_base AS dbase
            ON dbase.year = srpv.year
            AND dbase.month = srpv.month
            AND dbase.day = srpv.day
    WHERE
        srpv.ids_search_results_list IS NOT NULL
        AND UPPER(srpv.business_context) = 'RENT'
),
srpv AS (
    SELECT
        COUNT(*) AS search_results_page_viewed,
        hl.id_house_listing,
        srpv_explode.dt_day
    FROM
        srpv_explode
    JOIN
        datalake_ebdb_listing.house_listing AS hl
            ON hl.id_house = srpv_explode.id_house
            AND srpv_explode.ts_event >= hl.ts_listing_version_start
            AND srpv_explode.ts_event < COALESCE(hl.ts_listing_version_end, '2100-01-01')
    GROUP BY
        2, 3
),
visits_old_modeling AS (
    SELECT
        COUNT(DISTINCT rde.id_event) FILTER (WHERE rde.id_event_type = 1) AS visits_booked,
        COUNT(DISTINCT rde.id_event) FILTER (WHERE rde.id_event_type = 2) AS visits_completed,
        rde.id_house_listing,
        dbase.dt_day
    FROM
        datalake_rent_demand_events.rent_demand_events AS rde
    JOIN
        daily_base AS dbase
            ON dbase.dt_day = DATE(rde.ts_event)
    WHERE
        country_code = 'BR'
    GROUP BY
        3, 4
),
visits_new_modeling AS (
    SELECT
        COUNT(DISTINCT vse.id_schedule) FILTER (WHERE vse.event_type = 'VISIT_REQUESTED') AS visits_requested,
        COUNT(DISTINCT vse.id_schedule) FILTER (WHERE vse.event_type = 'VISIT_RESCHEDULED') AS visits_rescheduled,
        COUNT(DISTINCT vse.id_schedule) FILTER (WHERE vse.event_type = 'VISIT_CONFIRMED') AS visits_confirmed,
        COUNT(DISTINCT vse.id_schedule) FILTER (WHERE vse.event_type = 'VISIT_DONE') AS visits_done,
        hl.id_house_listing,
        dbase.dt_day
    FROM
        datalake_visit.visit_status_events AS vse
    JOIN
        datalake_ebdb_listing.house_listing AS hl
            ON hl.id_house = vse.id_house
            AND vse.ts_event_created >= hl.ts_listing_version_start
            AND vse.ts_event_created < COALESCE(hl.ts_listing_version_end, '2100-01-01')
    JOIN
        daily_base AS dbase
            ON dbase.dt_day = DATE(vse.ts_event_created)
    WHERE
        vse.country_code = 'BR'
        AND vse.business_context = 'RENT'
    GROUP BY
        5, 6
),
offers AS (
    SELECT
    COUNT(DISTINCT rde.id_event) AS offers_sent,
    rde.id_house_listing,
    dbase.dt_day
    FROM
        datalake_rent_demand_events.rent_demand_events AS rde
    JOIN
        daily_base AS dbase
            ON dbase.dt_day = DATE(rde.ts_event)
    WHERE
        rde.country_code = 'BR'
        AND rde.id_event_type = 3
    GROUP BY
        2, 3
),
favorite_set AS (
    SELECT
        COUNT(*) AS favorites,
        hl.id_house_listing,
        dbase.dt_day
    FROM
        datalake_amplitude_clean.170698_listing_favorite_set_events AS lfse
    JOIN
        daily_base AS dbase
            ON dbase.year = lfse.year
            AND dbase.month = lfse.month
            AND dbase.day = lfse.day
    JOIN
        datalake_ebdb_listing.house_listing AS hl
            ON hl.id_house = lfse.ep_house_id
            AND lfse.ts_event >= hl.ts_listing_version_start
            AND lfse.ts_event < COALESCE(hl.ts_listing_version_end, '2100-01-01')
    WHERE
        lfse.ep_house_id IS NOT NULL
        AND UPPER(lfse.business_context) = 'RENT'
    GROUP BY
        2, 3
),
listings_states_per_day AS (
    SELECT /*+ RANGE_JOIN(heh, 1180) */
        CONCAT(COALESCE(pled.id_house_listing, hl.id_house_listing), DATE_FORMAT(dbase.dt_day, 'yMMdd')) AS id_house_listing_day,
        COALESCE(pled.id_house_listing, hl.id_house_listing) AS id_house_listing,
        COALESCE(pled.id_house, hl.id_house) AS id_house,
        h.id_country,
        COALESCE(pled.id_contract, hl.id_contract) AS id_contract,
        h.id_user AS id_owner,
        heh.id_occupant,
        hbh.id_partner,
        lcod.id_partner AS id_partner_big_agent,
        h.id_region,
        hs.id_house_status,
        lpc.id_price_change,
        IF(h.is_rent_3p_supply, h.uuid_company, NULL) AS uuid_company,
        IF(h.is_rent_3p_supply, h.id_company_hubspot, NULL) AS id_company_hubspot,
        IF(h.is_rent_3p_supply, h.partner_3p_supply, NULL) AS partner_3p_supply,
        h.country_code,
        COALESCE(rl.rental_administrator, 'QUINTOANDAR') AS rental_administrator,
        lcod.consultant_type,
        heh.doorman_type,
        awk.first_key_location,
        heh.key_location,
        lpc.price AS rent,
        pred.calculator_min_price AS p_10,
        pred.calculator_p20_price AS p_20,
        pred.calculator_p30_price AS p_30,
        pred.calculator_p40_price AS p_40,
        pred.calculator_price AS p_50,
        pred.calculator_p60_price AS p_60,
        pred.calculator_p70_price AS p_70,
        pred.calculator_p80_price AS p_80,
        pred.calculator_max_price AS p_90,
        pred.calculator_certainty AS certainty,
        lpv.listing_page_viewed AS listing_page_views,
        srpv.search_results_page_viewed AS search_results_page_views,
        f.favorites,
        vom.visits_booked,
        vom.visits_completed,
        vnm.visits_requested,
        vnm.visits_rescheduled,
        vnm.visits_confirmed,
        vnm.visits_done,
        offers.offers_sent,
        DATEDIFF(DAY, DATE(lbcsh.ts_last_publication), dbase.dt_day) + 1 AS days_published,
        hls.status_history,
        hls.status_change_reason,
        hl.listing_category,
        hl.is_exclusive,
        CASE
            WHEN lbc.id_house IS NULL THEN TRUE -- When house is not in listing_business_context, it is for rent
            ELSE COALESCE(lbc.is_for_rent, FALSE)
        END AS is_for_rent,
        COALESCE(lbc.is_for_sale, FALSE) AS is_for_sale,
        h.is_rent_3p_supply,
        h.is_sale_3p_supply,
        b2b.is_b2b,
        /* is_last_status_of_day (house_listing_status) isn't enough to tell what is the last status
           when we extended it using the dim_date.
        */
        MAX(hls.ts_status_started) OVER(PARTITION BY dbase.dt_day, hls.id_house_listing) = hls.ts_status_started AS is_last_state_of_day,
        IF(dbase.dt_month_started = dbase.dt_day, TRUE, FALSE) AS is_month_start,
        IF(dbase.dt_month_ended = dbase.dt_day, TRUE, FALSE) AS is_month_end,
        IF(dbase.dt_week_started = dbase.dt_day, TRUE, FALSE) AS is_week_start,
        IF(dbase.dt_week_ended = dbase.dt_day, TRUE, FALSE) AS is_week_end,
        dbase.dt_day,
        lbcsh.ts_first_publication,
        lbcsh.ts_last_publication,
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
    LEFT JOIN
        previous_listing_early_demand AS pled
            ON hl.id_house_listing = pled.id_house_listing
    LEFT JOIN
        datalake_ebdb_contract.contract AS c
            ON pled.id_contract = c.id
    JOIN
        daily_base AS dbase
            ON (dbase.dt_day >= DATE(hls.ts_status_started)
                AND dbase.dt_day < COALESCE(DATE(hls.ts_status_ended), '2100-01-01'))
            OR (dbase.dt_day >= c.ts_created
                AND dbase.dt_day < COALESCE(c.dt_termination, CURRENT_DATE()))
    LEFT JOIN
        lbc
            ON lbc.id_house = hl.id_house
    LEFT JOIN
        datalake_ebdb_listing.house AS h
            ON COALESCE(pled.id_house, hl.id_house) = h.id
    LEFT JOIN
        last_ciq_of_day AS lcod
            ON COALESCE(pled.id_house, hl.id_house) = lcod.id_house
            AND dbase.dt_day = lcod.dt_day
            AND lcod.is_last_status_house_of_day = True
    LEFT JOIN
        datalake_ebdb_listing.house_entrance_history AS heh
            ON COALESCE(pled.id_house, hl.id_house) = heh.id_house
            AND dbase.dt_day >= DATE(heh.ts_entrance_started)
            AND dbase.dt_day < COALESCE(DATE(heh.ts_entrance_ended), '2100-01-01')
            AND heh.is_last_status_of_day = True
    LEFT JOIN
        datalake_ebdb_pricing.listing_price_change AS lpc
            ON COALESCE(pled.id_house, hl.id_house) = lpc.id_house
            AND dbase.dt_day >= DATE(lpc.ts_price_started)
            AND dbase.dt_day < COALESCE(DATE(lpc.ts_price_ended), '2100-01-01')
            AND lpc.is_last_price_of_day
            AND lpc.business_context = 'RENT'
    LEFT JOIN
        datalake_pro_owners.house_b2b_history AS hbh
            ON COALESCE(pled.id_house, hl.id_house) = hbh.id_house
            AND dbase.dt_day >= DATE(hbh.ts_started)
            AND dbase.dt_day < COALESCE(DATE(hbh.ts_ended), '2100-01-01')
            AND hbh.is_last_status_of_day = True
    LEFT JOIN
        datalake_ebdb_listing.agents_with_keys AS awk
            ON COALESCE(pled.id_house_listing, hl.id_house_listing) = awk.id_house_listing
    LEFT JOIN
        rent_listing AS rl
            ON COALESCE(pled.id_house, hl.id_house) = rl.id_house
    JOIN
        b2b
            ON COALESCE(pled.id_house, hl.id_house) = b2b.id_house
    LEFT JOIN
        datalake_ebdb_listing.house_status AS hs
            ON hls.status_history <=> hs.house_status
            AND hls.status_change_reason <=> hs.status_reason
    LEFT JOIN
        datalake_ebdb_listing.listing_business_context_status_history AS lbcsh
            ON COALESCE(pled.id_house, hl.id_house) = lbcsh.id_house
            AND lbcsh.business_context = 'RENT'
            AND dbase.dt_day >= DATE(lbcsh.ts_state_started)
            AND dbase.dt_day < COALESCE(DATE(lbcsh.ts_state_ended), '2100-01-01')
            AND lbcsh.is_last_state_of_day
    LEFT JOIN
        datalake_ebdb_pricing.listing_prediction_changes AS pred
            ON COALESCE(pled.id_house, hl.id_house) = pred.id_house
            AND dbase.dt_day >= DATE(pred.ts_calculator_result_started)
            AND dbase.dt_day < COALESCE(DATE(pred.ts_calculator_result_ended), '2100-01-01')
            AND pred.is_last_prediction_of_day
            AND pred.business_context = 'RENT'
    LEFT JOIN
        lpv
            ON COALESCE(pled.id_house_listing, hl.id_house_listing) = lpv.id_house_listing
            AND dbase.dt_day = lpv.dt_day
    LEFT JOIN
        srpv
            ON COALESCE(pled.id_house_listing, hl.id_house_listing) = srpv.id_house_listing
            AND dbase.dt_day = srpv.dt_day
    LEFT JOIN
        visits_old_modeling AS vom
            ON COALESCE(pled.id_house_listing, hl.id_house_listing) = vom.id_house_listing
            AND dbase.dt_day = vom.dt_day
    LEFT JOIN
        visits_new_modeling AS vnm
            ON COALESCE(pled.id_house_listing, hl.id_house_listing) = vnm.id_house_listing
            AND dbase.dt_day = vnm.dt_day
    LEFT JOIN
        offers
            ON COALESCE(pled.id_house_listing, hl.id_house_listing) = offers.id_house_listing
            AND dbase.dt_day = offers.dt_day
    LEFT JOIN
        favorite_set AS f
            ON COALESCE(pled.id_house_listing, hl.id_house_listing) = f.id_house_listing
            AND dbase.dt_day = f.dt_day
    /*
    This table is used for For_Rent and
    should be similar to fact_house_listing_status, so
    we are removing houses that are pure Sales from here.
    */
    WHERE
        lbc.id_house IS NULL
        OR lbc.is_for_rent
)
SELECT
    id_house_listing_day,
    id_house_listing,
    id_house,
    id_country,
    id_contract,
    id_owner,
    id_occupant,
    id_partner,
    id_partner_big_agent,
    id_region,
    id_house_status,
    id_price_change,
    uuid_company,
    id_company_hubspot,
    partner_3p_supply,
    country_code,
    rental_administrator,
    consultant_type,
    doorman_type,
    first_key_location,
    key_location,
    rent,
    p_10,
    p_20,
    p_30,
    p_40,
    p_50,
    p_60,
    p_70,
    p_80,
    p_90,
    certainty,
    listing_page_views,
    search_results_page_views,
    favorites,
    visits_booked,
    visits_completed,
    visits_requested,
    visits_rescheduled,
    visits_confirmed,
    visits_done,
    offers_sent,
    days_published,
    status_history,
    status_change_reason,
    listing_category,
    is_exclusive,
    is_for_rent,
    is_for_sale,
    is_rent_3p_supply,
    is_sale_3p_supply,
    is_b2b,
    is_month_start,
    is_month_end,
    is_week_start,
    is_week_end,
    dt_day,
    ts_first_publication,
    ts_last_publication,
    ts_status_started,
    ts_status_ended,
    year,
    month,
    day
FROM
    listings_states_per_day
WHERE
    is_last_state_of_day = TRUE
