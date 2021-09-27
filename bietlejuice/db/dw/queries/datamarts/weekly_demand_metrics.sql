WITH visit_booked AS (
    SELECT
        rf.sk_house_listing,
        dd1.week_start,
        COUNT(DISTINCT sk_booking) AS bookings,
        COUNT(DISTINCT CASE WHEN rf.flg_visit_completed > 0 THEN rf.sk_booking ELSE NULL END) AS vb2vc,
        COUNT(DISTINCT CASE WHEN sk_contract_signed_date > 0 AND date_diff('DAY', dd1.date, dd3.date) <= 28 THEN sk_contract ELSE NULL END) AS vb2cs_4w,
        COUNT(DISTINCT CASE WHEN sk_contract_signed_date > 0 AND date_diff('DAY', dd1.date, dd3.date) <= 56 THEN sk_contract ELSE NULL END) AS vb2cs_8w
    FROM 
        fact_listing_rent_flows rf
    JOIN 
        dim_date dd1
            ON dd1.sk_date = rf.sk_booking_created_date
    JOIN 
        dim_date dd2
            ON dd2.sk_date = rf.sk_visit_date
    JOIN 
        dim_date dd3
            ON dd3.sk_date = rf.sk_contract_signed_date
    WHERE 
        dd1.week_start > CURRENT_DATE - INTERVAL '26 WEEKS'
        AND rf.sk_booking > 0
    GROUP BY 1,2
  ),
visit_completed AS (
    SELECT
        rf.sk_house_listing,
        dd1.week_start,
        COUNT(DISTINCT CASE WHEN rf.flg_visit_completed > 0 AND rf.sk_offer_submitted_date > 0 AND date_diff('DAY', dd1.date, dd2.date) <= 28 THEN rf.sk_offer ELSE NULL END) AS vc2os_4w,
        COUNT(DISTINCT CASE WHEN rf.flg_visit_completed > 0 THEN rf.sk_booking ELSE NULL END) AS visits_completed
    FROM 
        fact_listing_rent_flows rf
    JOIN 
        dim_date dd1
            ON dd1.sk_date = rf.sk_visit_date
    JOIN 
        dim_date dd2
            ON dd2.sk_date = rf.sk_offer_submitted_date
    WHERE 
        dd1.week_start > CURRENT_DATE - INTERVAL '26 WEEKS'
    GROUP BY 1,2
),
offer_submitted AS (
    SELECT
        rf.sk_house_listing,
        dd1.week_start,
        COUNT(DISTINCT sk_offer) AS offer_submitted,
        COUNT(DISTINCT CASE WHEN sk_offer_approved_date > 0 THEN sk_offer ELSE NULL END) AS os2oa,
        COUNT(DISTINCT CASE WHEN sk_offer_approved_date > 0 AND date_diff('DAY',dd1.date, dd2.date) <= 14 THEN sk_offer ELSE NULL END) AS os2oa_2w
    FROM 
        fact_listing_rent_flows rf
    JOIN 
        dim_date dd1
            ON dd1.sk_date = rf.sk_offer_submitted_date
    JOIN 
        dim_date dd2
            ON dd2.sk_date = rf.sk_offer_approved_date
    WHERE 
        dd1.week_start > CURRENT_DATE - INTERVAL '26 WEEKS'
    GROUP BY 1,2
  ),
demand_metrics AS (
    SELECT
        COALESCE(vb.sk_house_listing,vc.sk_house_listing,os.sk_house_listing) AS sk_house_listing,
        COALESCE(vb.week_start,vc.week_start,os.week_start) AS week_start,
        SUM(vb.bookings) AS bookings,
        SUM(os.offer_submitted) AS offer_submitted,
        SUM(os.os2oa) AS os2oa,
        SUM(os.os2oa_2w) AS os2oa_2w,
        SUM(vb.vb2vc) AS vb2vc,
        SUM(vb.vb2cs_4w) AS vb2cs_4w,
        SUM(vb.vb2cs_8w) AS vb2cs_8w,
        SUM(vc.vc2os_4w) AS vc2os_4w,
        SUM(vc.visits_completed) AS visits_completed
    FROM 
        visit_booked vb
    FULL JOIN
        visit_completed vc 
            ON vc.sk_house_listing = vb.sk_house_listing 
            AND vc.week_start = vb.week_start
    FULL JOIN 
        offer_submitted os
            ON os.sk_house_listing = vb.sk_house_listing
            AND os.week_start = vb.week_start
    GROUP BY 1,2
)
SELECT
    LEFT(sk_house_listing,9) AS id_house,
    REPLACE(LEFT(sk_house_listing,9)||week_start, '-', '') AS id_house_week,
    week_start,
    SUM(bookings) AS bookings,
    SUM(offer_submitted) AS offer_submitted,
    SUM(os2oa) AS os2oa,
    SUM(os2oa_2w) AS os2oa_2w,
    SUM(vb2vc) AS vb2vc,
    SUM(vb2cs_4w) AS vb2cs_4w,
    SUM(vb2cs_8w) AS vb2cs_8w,
    SUM(vc2os_4w) AS vc2os_4w,
    SUM(visits_completed) AS visits_completed
FROM 
    demand_metrics
GROUP BY 1,2,3 