WITH unconverted_events AS (
  /** As unconverted events will always have weeks_to_conversion = -1, we need to group it separately
    so we can join it later. **/
    SELECT
        rc.country_code,
        rc.halfyear,
        rc.quarter,
        rc.business_type,
        rc.city_group,
        rc.tier,
        rc.listing_category_start,
        rc.rent_flow_origin,
        rc.rental_administrator,
        COALESCE(SUM(rc.vb_unconverted), 0) AS vb_unconverted,
        COALESCE(SUM(rc.vc_unconverted), 0) AS vc_unconverted,
        COALESCE(SUM(rc.os_unconverted), 0) AS os_unconverted,
        COALESCE(SUM(rc.oa_unconverted), 0) AS oa_unconverted,
        COALESCE(SUM(rc.es_unconverted), 0) AS es_unconverted,
        COALESCE(SUM(rc.ep_unconverted), 0) AS ep_unconverted,
        COALESCE(SUM(rc.ds_unconverted), 0) AS ds_unconverted,
        COALESCE(SUM(rc.ca_unconverted), 0) AS ca_unconverted,
        COALESCE(SUM(rc.cc_unconverted), 0) AS cc_unconverted,
        rc.has_guarantee,
        rc.dt_event,
        rc.dt_week_started
    FROM
        dw_rent_snapshot.rent_cohort_conversions_snapshot AS rc
    WHERE
        year = YEAR(NOW())
        AND month = MONTH(NOW())
        AND day = DAY(NOW())
        AND weeks_to_conversion = -1
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 19, 20, 21
),
base AS (
    SELECT
        rc.country_code,
        rc.halfyear,
        rc.quarter,
        rc.business_type,
        rc.city_group,
        rc.tier,
        rc.listing_category_start,
        rc.rent_flow_origin,
        rc.rental_administrator,
        rc.weeks_to_conversion,
        COALESCE(SUM(rc.vb_converted_vc), 0) AS vb_converted_vc,
        COALESCE(SUM(rc.vb_converted_os), 0) AS vb_converted_os,
        COALESCE(SUM(rc.vb_converted_oa), 0) AS vb_converted_oa,
        COALESCE(SUM(rc.vb_converted_cs), 0) AS vb_converted_cs,
        COALESCE(SUM(rc.vc_converted_os), 0) AS vc_converted_os,
        COALESCE(SUM(rc.os_converted_oa), 0) AS os_converted_oa,
        COALESCE(SUM(rc.os_converted_cs), 0) AS os_converted_cs,
        COALESCE(SUM(rc.oa_converted_es), 0) AS oa_converted_es,
        COALESCE(SUM(rc.oa_converted_ds), 0) AS oa_converted_ds,
        COALESCE(SUM(rc.oa_converted_ca), 0) AS oa_converted_ca,
        COALESCE(SUM(rc.oa_converted_cs), 0) AS oa_converted_cs,
        COALESCE(SUM(rc.es_converted_ep), 0) AS es_converted_ep,
        COALESCE(SUM(rc.es_converted_ca), 0) AS es_converted_ca,
        COALESCE(SUM(rc.ep_converted_ds), 0) AS ep_converted_ds,
        COALESCE(SUM(rc.ds_converted_ca), 0) AS ds_converted_ca,
        COALESCE(SUM(rc.ca_converted_cc), 0) AS ca_converted_cc,
        COALESCE(SUM(rc.ca_converted_cs), 0) AS ca_converted_cs,
        COALESCE(SUM(rc.cc_converted_cs), 0) AS cc_converted_cs,
        rc.has_guarantee,
        rc.dt_event,
        rc.dt_week_started
    FROM
        dw_rent_snapshot.rent_cohort_conversions_snapshot AS rc
    WHERE
        year = YEAR(NOW())
        AND month = MONTH(NOW())
        AND day = DAY(NOW())
        AND weeks_to_conversion > -1
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 29, 30, 31
)
SELECT
    b.country_code,
    b.halfyear,
    b.quarter,
    b.business_type,
    b.city_group,
    b.tier,
    b.listing_category_start,
    b.rent_flow_origin,
    b.rental_administrator,
    b.weeks_to_conversion,
    COALESCE(CAST((vb_converted_vc/(vb_converted_vc + vb_unconverted)) AS DECIMAL (10,2)), 0.00) AS vb2vc,
    COALESCE(CAST((vb_converted_os/(vb_converted_os + vb_unconverted)) AS DECIMAL (10,2)), 0.00) AS vb2os,
    COALESCE(CAST((vb_converted_oa/(vb_converted_oa + vb_unconverted)) AS DECIMAL (10,2)), 0.00) AS vb2oa,
    COALESCE(CAST((vb_converted_cs/(vb_converted_cs + vb_unconverted)) AS DECIMAL (10,2)), 0.00) AS vb2cs,
    COALESCE(CAST((vc_converted_os/(vc_converted_os + vc_unconverted)) AS DECIMAL (10,2)), 0.00) AS vc2os,
    COALESCE(CAST((os_converted_oa/(os_converted_oa + os_unconverted)) AS DECIMAL (10,2)), 0.00) AS os2oa,
    COALESCE(CAST((os_converted_cs/(os_converted_cs + os_unconverted)) AS DECIMAL (10,2)), 0.00) AS os2cs,
    COALESCE(CAST((oa_converted_es/(oa_converted_es + oa_unconverted)) AS DECIMAL (10,2)), 0.00) AS oa2es,
    COALESCE(CAST((oa_converted_ds/(oa_converted_ds + oa_unconverted)) AS DECIMAL (10,2)), 0.00) AS oa2ds,
    COALESCE(CAST((oa_converted_ca/(oa_converted_ca + oa_unconverted)) AS DECIMAL (10,2)), 0.00) AS oa2ca,
    COALESCE(CAST((oa_converted_cs/(oa_converted_cs + oa_unconverted)) AS DECIMAL (10,2)), 0.00) AS oa2cs,
    COALESCE(CAST((es_converted_ep/(es_converted_ep + es_unconverted)) AS DECIMAL (10,2)), 0.00) AS es2ep,
    COALESCE(CAST((es_converted_ca/(es_converted_ca + es_unconverted)) AS DECIMAL (10,2)), 0.00) AS es2ca,
    COALESCE(CAST((ep_converted_ds/(ep_converted_ds + ep_unconverted)) AS DECIMAL (10,2)), 0.00) AS ep2ds,
    COALESCE(CAST((ds_converted_ca/(ds_converted_ca + ds_unconverted)) AS DECIMAL (10,2)), 0.00) AS ds2ca,
    COALESCE(CAST((ca_converted_cc/(ca_converted_cc + ca_unconverted)) AS DECIMAL (10,2)), 0.00) AS ca2cc,
    COALESCE(CAST((ca_converted_cs/(ca_converted_cs + ca_unconverted)) AS DECIMAL (10,2)), 0.00) AS ca2cs,
    COALESCE(CAST((cc_converted_cs/(cc_converted_cs + cc_unconverted)) AS DECIMAL (10,2)), 0.00) AS cc2cs,
    b.has_guarantee,
    b.dt_event,
    b.dt_week_started,
    NOW() AS ts_load
FROM
    base AS b
JOIN
    unconverted_events AS u
      ON b.halfyear = u.halfyear
      AND b.quarter = u.quarter
      AND b.business_type = u.business_type
      AND b.city_group = u.city_group
      AND b.tier = u.tier
      AND b.listing_category_start = u.listing_category_start
      AND b.rent_flow_origin = u.rent_flow_origin
      AND b.rental_administrator = u.rental_administrator
      AND b.has_guarantee = u.has_guarantee
      AND b.dt_event = u.dt_event
      AND b.dt_week_started = u.dt_week_started
      AND b.country_code = u.country_code
