WITH visit_fitting AS (
    SELECT
        vf.id,
        vf.id_visit,
        vf.id_visitor,
        lh.id_user AS id_owner,
        vf.id_house,
        hl.id_house_listing,
        LEAD(vf.id) OVER (PARTITION BY vf.id_visitor, vf.id_house, vf.dt_visit ORDER BY vf.ts_created) AS id_next_visit_fitting_after_discard,
        hl.country_code,
        vf.business_context,
        vf.intention,
        vf.status,
        vf.channel,
        vf.request_context,
        vf.dt_visit AS dt_visit_desired,
        TO_UTC_TIMESTAMP(
            (
                CAST(vf.dt_visit AS TIMESTAMP)
                + FLOOR((vf.begin_slot * 15 / 60)+8) * INTERVAL 1 HOURS
                + ABS(vf.begin_slot * 15 % 60) * INTERVAL 1 MINUTES
            ),
            COALESCE(ct.default_timezone, 'UTC')
        ) AS ts_visit_desired_begin_local_tz,
        TO_UTC_TIMESTAMP(
            (
                CAST(vf.dt_visit AS TIMESTAMP)
                + FLOOR((vf.end_slot * 15 / 60)+8) * INTERVAL 1 HOURS
                + ABS(vf.end_slot * 15 % 60) * INTERVAL 1 MINUTES
            ),
            COALESCE(ct.default_timezone, 'UTC')
        ) AS ts_visit_desired_end_local_tz,
        vf.ts_expiration,
        vf.ts_created,
        vf.ts_updated
    FROM
        datalake_ebdb_clean.visit_fitting AS vf
    INNER JOIN
        datalake_ebdb_listing.house_listing AS hl
            ON vf.id_house = hl.id_house
            AND vf.ts_created >= hl.ts_listing_version_start
            AND (
                vf.ts_created <= hl.ts_listing_version_end
                OR hl.ts_listing_version_end IS NULL
            )
    INNER JOIN
        datalake_ebdb_clean.country AS ct
            ON ct.code = hl.country_code
    INNER JOIN
        datalake_ebdb_listing.house AS lh
            ON lh.id = vf.id_house
    WHERE
        DATE(vf.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
visit_intent_events AS (
    SELECT 
        vf.id,
        vf.id_visitor,
        vf.id_house,
        vf.status,
        MAX(vf2.id_house IS NOT NULL) FILTER (WHERE vf.status = "EXPIRED" AND DATE(vf2.ts_updated) >= DATE(vf.ts_expiration)) AS has_fitted_visit_after_expired,
        MAX(vf.id_house = vf2.id_house) FILTER (WHERE vf.status = "EXPIRED" AND DATE(vf2.ts_updated) >= DATE(vf.ts_expiration)) AS has_fitted_visit_after_expired_in_same_house,
        COALESCE(MAX(vf2.id_house IS NOT NULL), FALSE) AS has_fitted_visit_all_5a_journey
    FROM 
        visit_fitting AS vf
    LEFT JOIN
        visit_fitting AS vf2
            ON vf2.id_visitor = vf.id_visitor
            AND vf2.status = "FITTED"
    GROUP BY ALL
)
SELECT
    vf.id,
    vf.id_visit,
    vf.id_visitor,
    vf.id_owner,
    vf.id_house,
    vf.id_house_listing,
    vf.id_next_visit_fitting_after_discard,
    vf.country_code,
    vf.business_context,
    vf.intention,
    vf.status,
    vf.channel,
    vf.request_context,
    vie.has_fitted_visit_after_expired,
    vie.has_fitted_visit_after_expired_in_same_house,
    vie.has_fitted_visit_all_5a_journey,
    vf.dt_visit_desired,
    vf.ts_visit_desired_begin_local_tz,
    vf.ts_visit_desired_end_local_tz,
    vf.ts_expiration,
    vf.ts_created,
    vf.ts_updated,
    YEAR(vf.ts_updated) AS year,
    MONTH(vf.ts_updated) AS month,
    DAY(vf.ts_updated) AS day
FROM 
    visit_fitting AS vf
JOIN
    visit_intent_events AS vie
      ON vie.id = vf.id