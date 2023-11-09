SELECT
    rc.halfyear,
    rc.quarter,
    rc.business_type,
    rc.city_group,
    rc.tier,
    rc.listing_category_start,
    rc.rent_flow_origin,
    rc.rental_administrator,
    rc.weeks_to_conversion,
    CAST(rc.vb_converted_vc/rd.visits_booked AS DECIMAL (2,2)) AS vb2vc,
    CAST(rc.vb_converted_os/rd.visits_booked AS DECIMAL (2,2)) AS vb2os,
    CAST(rc.vb_converted_oa/rd.visits_booked AS DECIMAL (2,2)) AS vb2oa,
    CAST(rc.vb_converted_cs/rd.visits_booked AS DECIMAL (2,2)) AS vb2cs,
    CAST(rc.vc_converted_os/rd.visits_completed AS DECIMAL (2,2)) AS vc2os,
    CAST(rc.os_converted_oa/rd.offers_submitted AS DECIMAL (2,2)) AS os2oa,
    CAST(rc.os_converted_cs/rd.offers_submitted AS DECIMAL (2,2)) AS os2cs,
    CAST(rc.oa_converted_es/rd.offers_accepted AS DECIMAL (2,2)) AS oa2es,
    CAST(rc.oa_converted_ds/rd.offers_accepted AS DECIMAL (2,2)) AS oa2ds,
    CAST(rc.oa_converted_ca/rd.offers_accepted AS DECIMAL (2,2)) AS oa2ca,
    CAST(rc.oa_converted_cs/rd.offers_accepted AS DECIMAL (2,2)) AS oa2cs,
    CAST(rc.es_converted_ep/rd.evaluation_started AS DECIMAL (2,2)) AS es2ep,
    CAST(rc.es_converted_ca/rd.evaluation_started AS DECIMAL (2,2)) AS es2ca,
    CAST(rc.ep_converted_ds/rd.evaluation_positive AS DECIMAL (2,2)) AS ep2ds,
    CAST(rc.ds_converted_ca/rd.documentation_sent AS DECIMAL (2,2)) AS ds2ca,
    CAST(rc.ca_converted_cs/rd.credit_approved AS DECIMAL (2,2)) AS ca2cs,
    CAST(rc.cc_converted_cs/rd.contract_created AS DECIMAL (2,2)) AS cc2cs,
    rc.has_guarantee,
    rc.dt_event,
    rc.dt_week_started,
    rc.country_code,
    NOW() AS ts_load
FROM
    dw_rent_snapshot.rent_cohort_conversions_snapshot AS rc
JOIN
    dw_rent_snapshot.rent_demand_events_snapshot AS rd
        ON rc.year = YEAR(NOW())
        AND rc.month = MONTH(NOW())
        AND rc.day = DAY(NOW())
        AND rc.halfyear = rd.halfyear
        AND rc.quarter = rd.quarter
        AND rc.business_type = rd.business_type
        AND rc.city_group = rd.city_group
        AND rc.tier = rd.tier
        AND rc.listing_category_start = rd.listing_category_start
        AND rc.rent_flow_origin = rd.rent_flow_origin
        AND rc.rental_administrator = rd.rental_administrator
        AND rc.has_guarantee = rd.has_guarantee
        AND rc.country_code = rd.country_code
        AND rc.dt_event = rd.dt_event
        AND rc.dt_week_started = rd.dt_week_started
