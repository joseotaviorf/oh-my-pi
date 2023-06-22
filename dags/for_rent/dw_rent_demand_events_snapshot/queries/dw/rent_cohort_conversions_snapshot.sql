SELECT
    DATE_FORMAT(CURRENT_DATE, 'yyyyMMdd') AS id_snapshot,
    CASE 
        WHEN MONTH(TO_DATE(CAST(fc.sk_base_event_date AS STRING), 'yyyyMMdd')) <= 6 THEN 1
        ELSE 2
    END AS halfyear,
    EXTRACT(quarter FROM dt.date) AS quarter,
    dr.city_group,
    dr.tier,
    CASE 
        WHEN dhl.is_b2b = TRUE THEN 'B2B'
        WHEN dhl.first_consultant_type = 'CIQ_MANAGER' THEN 'ASP'
        WHEN dhl.is_for_rent = TRUE AND (dhl.first_consultant_type IS NOT NULL AND dhl.first_consultant_type <> 'Core') THEN dhl.first_consultant_type
        WHEN dhl.is_b2b = FALSE OR (dhl.first_consultant_type IS NULL OR dhl.first_consultant_type = 'Core') THEN 'CORE'
    END AS business_type,
    CASE 
        WHEN fdf.funnel_first_touchpoint = 'DIRECT' THEN fdf.funnel_first_touchpoint
        ELSE 'VISIT' 
    END AS rent_flow_origin,
    dhl.rental_administrator,
    fc.days_to_conversion,
    fc.weeks_to_conversion,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '1-2') AS vb2vc,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '1-3') AS vb2os,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '1-4') AS vb2oa,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '1-5') AS vb2es,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '1-6') AS vb2ep,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '1-7') AS vb2ds,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '1-8') AS vb2ca,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '1-9') AS vb2cs,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '2-3') AS vc2oa,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '2-4') AS vc2os,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '2-5') AS vc2es,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '2-6') AS vc2ep,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '2-7') AS vc2ds,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '2-8') AS vc2ca,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '2-9') AS vc2cs,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '3-4') AS os2oa,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '3-4') AS os2es,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '3-6') AS os2ep,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '3-7') AS os2ds,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '3-8') AS os2ca,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '3-9') AS os2cs,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '4-5') AS oa2es,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '4-6') AS oa2ep,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '4-7') AS oa2ds,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '4-8') AS oa2ca,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '4-9') AS oa2cs,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '5-6') AS es2ep,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '5-7') AS es2ds,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '5-8') AS es2ca,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '5-9') AS es2cs,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '6-7') AS ep2ds,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '6-8') AS ep2ca,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '6-9') AS ep2cs,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '7-8') AS ds2ca,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '7-9') AS ds2cs,
    COUNT(DISTINCT fc.sk_cohort_conversion) FILTER (WHERE fc.sk_cohort_type = '8-9') AS ca2cs,
    CASE
        WHEN fc.sk_base_event_type BETWEEN 1 AND 4 THEN FALSE
        WHEN fc.sk_base_event_type > 4 AND dp.guarantee = 'RentalGuarantee' THEN TRUE
        ELSE FALSE
    END AS has_guarantee,
    TO_DATE(dt.date, 'yyyy-mm-dd') AS dt_event,  
    TO_DATE(DATE_TRUNC('week', dt.date), 'yyyy-mm-dd') AS dt_week_started,
    NOW() AS ts_snapshot,
    fc.country_code,
    YEAR(fc.ts_load) AS year,
    MONTH(fc.ts_load) AS month,
    DAY(fc.ts_load) AS day
FROM
    dw_rent.fact_rent_cohort_conversions AS fc
JOIN 
    dw_public.dim_date AS dt
        ON dt.sk_date = fc.sk_base_event_date
LEFT JOIN 
    dw_public.dim_region AS dr
        ON dr.sk_region = fc.sk_region
LEFT JOIN 
    dw_public.dim_house_listing AS dhl
        ON fc.sk_house_listing = dhl.sk_house_listing 
LEFT JOIN 
    dw_datamarts.funnel_demand_flows AS fdf
        ON fc.sk_rent_flow = fdf.sk_rent_flow        
        AND fc.sk_house_listing = fdf.sk_house_listing
LEFT JOIN 
    dw_public.dim_proposal AS dp
        ON fc.sk_proposal = dp.sk_proposal
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 47, 48, 49, 50, 51, 52, 53, 54