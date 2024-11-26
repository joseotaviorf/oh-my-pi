WITH listing_base AS (
  SELECT 
    dhl.ts_listing_version_start::DATE AS listing_start_dt,
    dhl.listing_category_start AS listing_category_start,
    dr.city_group,
    dr.city_name,
    dr.region_code,
    CASE
      WHEN dhl.ts_early_demand_started IS NOT NULL THEN true
      ELSE false
    END AS is_early_demand,
    dhl.sk_house_listing,
    dhl.id_house,
    COALESCE(dhl.rent, dhl.house_rent) AS rent
  FROM 
    dw_public.dim_house_listing AS dhl
  LEFT JOIN 
    dw_public.fact_house_listings AS fhl 
      ON fhl.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN 
    dw_public.dim_region AS dr 
      ON dr.sk_region = fhl.sk_region
  WHERE 
    (dr.country_code = 'BR' OR dr.country_code IS NULL)
    AND (dhl.version > 0)
    AND (dhl.status IN ('publicado', 'PUBLISHED'))
    AND (dhl.ts_listing_version_start::DATE >= '2023-10-01'::DATE)
),
days_published AS (
  SELECT 
    dhl.sk_house_listing,
    DATE(dhl.ts_listing_version_start) AS dt_publication,
    COUNT(
      DISTINCT 
      CASE
        WHEN hldi.status_history in ('publicado', 'PUBLISHED') AND hldi.dt_day >= date_add (DAY, -7, CURRENT_DATE) THEN hldi.dt_day
        ELSE NULL
      END
    ) AS days_pub_7, 
    COUNT(
      DISTINCT 
      CASE
        WHEN hldi.status_history in ('publicado', 'PUBLISHED') AND hldi.dt_day >= date_add (DAY, -3, CURRENT_DATE) THEN hldi.dt_day
        ELSE NULL
      END
    ) AS days_pub_3,
    COUNT(
      DISTINCT 
      CASE
        WHEN hldi.status_history in ('publicado', 'PUBLISHED') AND hldi.dt_day >= date_add (DAY, -1, CURRENT_DATE) THEN hldi.dt_day
        ELSE NULL
      END
    ) AS days_pub_1
  FROM 
    dw_public.dim_house_listing AS dhl
  LEFT JOIN 
    datalake_rental_historical_follow_up.house_listings_daily_info AS hldi
      ON (hldi.id_house_listing = dhl.sk_house_listing)
      AND (hldi.dt_day BETWEEN dhl.ts_listing_version_start::DATE AND COALESCE(dhl.ts_listing_version_END::DATE, CURRENT_DATE::DATE))
  WHERE (dhl.version > 0)
    AND (dhl.ts_listing_version_start >= date '2023-10-01')
  GROUP BY 1, 2
),
lpv_amplitude AS (
  SELECT 
    ts_client_event::DATE AS dt_event,
    CASE
      WHEN ep_house_id LIKE '%.%' THEN NULL
      ELSE ep_house_id::BIGINT
    END AS id_house,
    COUNT(1) AS lpv
  FROM 
    datalake_amplitude_clean.170698_listing_page_viewed_events
  WHERE 
    (year >= 2023)
    AND (ts_client_event::DATE >= '2023-10-01'::DATE)
    AND (LOWER(business_context) = 'rent')
  GROUP BY 1, 2
),
lpv AS (
  SELECT 
    dhl.ts_publication::DATE AS dt_publication,
    dhl.sk_house_listing,
    p.days_pub_7,
    p.days_pub_3,
    p.days_pub_1,
    SUM(CASE WHEN lpv_amplitude.dt_event >= DATE_ADD(DAY, -7, CURRENT_DATE) THEN lpv_amplitude.lpv ELSE 0 END) AS lpv_7d,
    SUM(CASE WHEN lpv_amplitude.dt_event >= DATE_ADD(DAY, -7, CURRENT_DATE) THEN lpv_amplitude.lpv ELSE 0 END)/(CASE WHEN p.days_pub_7 = 0 THEN 1 ELSE p.days_pub_7 END)::DOUBLE AS avg_lpv_days_pub_7d,
    SUM(CASE WHEN lpv_amplitude.dt_event >= DATE_ADD(DAY, -3, CURRENT_DATE) THEN lpv_amplitude.lpv ELSE 0 END) AS lpv_3d,
    SUM(CASE WHEN lpv_amplitude.dt_event >= DATE_ADD(DAY, -3, CURRENT_DATE) THEN lpv_amplitude.lpv ELSE 0 END)/(CASE WHEN p.days_pub_3 = 0 THEN 1 ELSE p.days_pub_3 END)::DOUBLE AS avg_lpv_days_pub_3d,
    SUM(CASE WHEN lpv_amplitude.dt_event >= DATE_ADD(DAY, -1, CURRENT_DATE) THEN lpv_amplitude.lpv ELSE 0 END) AS lpv_1d,
    SUM(CASE WHEN lpv_amplitude.dt_event >= DATE_ADD(DAY, -1, CURRENT_DATE) THEN lpv_amplitude.lpv ELSE 0 END)/(CASE WHEN p.days_pub_1 = 0 THEN 1 ELSE p.days_pub_1 END)::DOUBLE AS avg_lpv_days_pub_1d
  FROM 
    dw_public.dim_house_listing AS dhl
  LEFT JOIN 
    lpv_amplitude
    ON (lpv_amplitude.id_house = dhl.id_house)
      AND (lpv_amplitude.dt_event::DATE BETWEEN dhl.ts_listing_version_start::DATE AND COALESCE(dhl.ts_listing_version_end::DATE, CURRENT_DATE))
  LEFT JOIN 
    days_published AS p 
      ON (p.sk_house_listing = dhl.sk_house_listing)
  WHERE 
    (dhl.version > 0)
    AND (dhl.ts_listing_version_start::DATE >= '2023-10-01'::DATE)
  GROUP BY 1, 2, 3, 4, 5
),
booking_availability_hours AS (
  SELECT 
    id_house,
    dt_available_started::DATE AS start_date,
    day_of_week,
    DATE_ADD(DAY, -1,
      COALESCE(
        LEAD(dt_available_started, 1) OVER (PARTITION BY id_house, day_of_week ORDER BY dt_available_started ASC), CURRENT_DATE
      )
    ) AS end_date,
    day_hours_available
  FROM 
    datalake_booking.house_available_hours
),
available_hours AS (
  SELECT 
    dt.date,
    ah.id_house,
    SUM(ah.day_hours_available) AS hours_available
  FROM 
    booking_availability_hours AS ah
  CROSS JOIN 
    dw_public.dim_date dt
      ON (dt.date BETWEEN ah.start_date AND ah.end_date)
  GROUP BY 1, 2
),
scores AS (
  SELECT 
    hdi.dt_day,
    dhl.sk_house_listing,
    dhl.ts_publication::DATE AS dt_published,
    hdi.listing_category,
    dr.city_name,
    hdi.rent,
    hdi.p_90,
    hdi.key_location,
    hdi.is_exclusive,
    ah.hours_available,
    CASE
      WHEN hdi.rent IS NULL OR hdi.p_90 IS NULL THEN 0.0
      WHEN hdi.rent IS NOT NULL AND hdi.p_90 IS NOT NULL AND hdi.rent > 1.45 * hdi.p_90 THEN 0.0
      WHEN hdi.rent IS NOT NULL AND hdi.p_90 IS NOT NULL AND hdi.rent > 1.30 * hdi.p_90 THEN 1.0
      WHEN hdi.rent IS NOT NULL AND hdi.p_90 IS NOT NULL AND hdi.rent > 1.15 * hdi.p_90 THEN 2.0
      WHEN hdi.rent IS NOT NULL AND hdi.p_90 IS NOT NULL AND hdi.rent > hdi.p_90 THEN 3.0
      ELSE 4.0
    END AS well_priced_score,
    CASE
      WHEN ah.hours_available >= 33 AND ah.hours_available <> 64 THEN 1.0
      WHEN ah.hours_available >= 15 AND ah.hours_available <> 64 THEN 0.5
      ELSE 0.0
    END AS good_hours_score,
    CASE
      WHEN hdi.key_location in ('OwnerPresent', 'None') OR hdi.key_location IS NULL THEN 0.0
      ELSE 2.7
    END AS is_easy_entry_score,
    CASE
      WHEN hdi.is_exclusive = TRUE THEN 2.3
      ELSE 0.0
    END AS is_exclusive_score
  FROM 
    datalake_rental_historical_follow_up.house_listings_daily_info AS hdi
  JOIN 
    dw_public.dim_house_listing dhl
      ON dhl.sk_house_listing = hdi.id_house_listing
  JOIN 
    dw_public.dim_region dr
      ON dr.sk_region = hdi.id_region
  LEFT JOIN 
    available_hours ah
      ON ah.id_house = dhl.id_house
        AND ah.date = hdi.dt_day
  WHERE hdi.status_history IN ('publicado', 'PUBLISHED')
    AND hdi.dt_day = date_add(DAY, -1, CURRENT_DATE)
    AND dhl.version <> 0
    AND dr.city_group IS NOT NULL
    AND dr.country_code <> 'MX'
  GROUP BY ALL
),
final_db AS (
  SELECT 
    dd.month_start AS listing_pub_mth,
    dd.date AS listing_pub_dt,
    CASE
      WHEN DATE_DIFF(MONTH, dd.date, CURRENT_DATE) < 1 THEN 'M0'
      WHEN DATE_DIFF(MONTH, dd.date, CURRENT_DATE) < 2 THEN 'M1'
      WHEN DATE_DIFF(MONTH, dd.date, CURRENT_DATE) < 3 THEN 'M2'
      WHEN DATE_DIFF(MONTH, dd.date, CURRENT_DATE) < 4 THEN 'M3'
      WHEN DATE_DIFF(MONTH, dd.date, CURRENT_DATE) < 5 THEN 'M4'
      WHEN DATE_DIFF(MONTH, dd.date, CURRENT_DATE) < 6 THEN 'M5'
      WHEN DATE_DIFF(MONTH, dd.date, CURRENT_DATE) < 7 THEN 'M6'
      WHEN DATE_DIFF(MONTH, dd.date, CURRENT_DATE) < 8 THEN 'M7'
      WHEN DATE_DIFF(MONTH, dd.date, CURRENT_DATE) < 9 THEN 'M8'
      WHEN DATE_DIFF(MONTH, dd.date, CURRENT_DATE) < 10 THEN 'M9'
      WHEN DATE_DIFF(MONTH, dd.date, CURRENT_DATE) < 11 THEN 'M10'
      WHEN DATE_DIFF(MONTH, dd.date, CURRENT_DATE) < 12 THEN 'M11'
      WHEN DATE_DIFF(MONTH, dd.date, CURRENT_DATE) < 13 THEN 'M12'
      ELSE 'M12+'
    END AS listing_age,
    bd.listing_category_start,
    bd.city_group,
    bd.city_name,
    bd.region_code,
    bd.sk_house_listing,
    bd.id_house AS id_house,
    bd.rent,
    lpv.lpv_7d AS lpv_7d,
    ROUND(lpv.avg_lpv_days_pub_7d, 2) AS avg_lpv_days_pub_7d,
    ROUND(lpv.avg_lpv_days_pub_3d, 2) AS avg_lpv_days_pub_3d,
    ROUND(lpv.avg_lpv_days_pub_1d, 2) AS avg_lpv_days_pub_1d,
    s.well_priced_score,
    s.good_hours_score,
    s.is_easy_entry_score,
    s.is_exclusive_score,
    s.well_priced_score + s.good_hours_score + s.is_easy_entry_score + s.is_exclusive_score AS changeable_characteristics_score
  FROM 
    listing_base AS bd
  LEFT JOIN 
    lpv 
      ON lpv.sk_house_listing = bd.sk_house_listing
  LEFT JOIN 
    days_published AS p 
      ON p.sk_house_listing = bd.sk_house_listing
  LEFT JOIN 
    scores AS s 
      ON bd.sk_house_listing = s.sk_house_listing
  LEFT JOIN 
    dw_public.dim_date AS dd 
      ON dd.date = bd.listing_start_dt
),
for_rent_score AS (
  SELECT 
    id_house,
    listing_age,
    sk_house_listing,
    city_group,
    city_name,
    region_code,
    avg_lpv_days_pub_1d AS qt_lpv_1d_for_rent,
    avg_lpv_days_pub_3d AS qt_lpv_3d_for_rent,
    avg_lpv_days_pub_7d AS qt_lpv_7d_for_rent,
    well_priced_score AS quality_score,
    listing_pub_dt AS dt_publication
  FROM 
    final_db
  WHERE 
    -- Only listings with more than 3 days
    DATE_DIFF(DAY, listing_pub_dt, CURRENT_DATE) >= 3 
),
for_sale_score AS (
  SELECT 
    ol.sk_house AS id_house,
    ls.liquidity_score,
    dr.city_group,
    dr.city_name,
    dr.region_code,
    if(date(dhl.ts_last_publication) is null,date(dhl.ts_first_publication),date(dhl.ts_first_publication)) as dt_publication,
    ROUND(AVG(CASE WHEN d.date >= DATE_ADD(DAY,-1,CURRENT_DATE) THEN ol.qt_listing_page_viewed END),1) AS qt_lpv_1d_for_sale,
    ROUND(AVG(CASE WHEN d.date >= DATE_ADD(DAY,-3,CURRENT_DATE) THEN ol.qt_listing_page_viewed END),1) AS qt_lpv_3d_for_sale,
    ROUND(AVG(CASE WHEN d.date >= DATE_ADD(DAY,-7,CURRENT_DATE) THEN ol.qt_listing_page_viewed END),1) AS qt_lpv_7d_for_sale
  FROM 
    dw_sale.fact_daily_ongoing_listing AS ol
  LEFT JOIN 
    dw_public.dim_date AS d
      ON d.sk_date = ol.sk_snapshot_date
  LEFT JOIN 
    dw_sale.dim_listing AS dhl
      ON dhl.sk_house = ol.sk_house
  LEFT JOIN 
    dw_sale.fact_listings AS fl 
      ON fl.sk_house = dhl.sk_house
  LEFT JOIN
    dw_public.dim_region AS dr 
      ON dr.sk_region = fl.sk_region
  LEFT JOIN 
    sales_liquidity_score.predicted_scores ls
      ON ls.sk_house = ol.sk_house
  WHERE 
    d.date >= DATE_ADD(DAY,-7,CURRENT_DATE)
  GROUP BY 1,2,3,4,5,6
),
results AS (
  SELECT 
    COALESCE(fr.id_house, fs.id_house) AS id_house,
    fr.sk_house_listing AS id_house_listing,
    COALESCE(fr.city_group, fs.city_group) AS city_group,
    COALESCE(fr.city_name, fs.city_name) AS city_name,
    COALESCE(fr.region_code, fs.region_code) AS region_code,
    fr.listing_age,
    fr.quality_score,
    fs.liquidity_score,
    fr.qt_lpv_1d_for_rent,
    fr.qt_lpv_3d_for_rent,
    fr.qt_lpv_7d_for_rent,
    fr.dt_publication AS dt_publication_for_rent,
    fs.qt_lpv_1d_for_sale,
    fs.qt_lpv_3d_for_sale,
    fs.qt_lpv_7d_for_sale,
    fs.dt_publication AS dt_publication_for_sale,
    CASE
      WHEN liquidity_score >= 0 AND liquidity_score < 10 THEN 'A'
      WHEN liquidity_score >= 10 AND liquidity_score < 20 THEN 'B'
      WHEN liquidity_score >= 20 AND liquidity_score < 30 THEN 'C'
      WHEN liquidity_score >= 30 AND liquidity_score < 40 THEN 'D'
      WHEN liquidity_score >= 40 AND liquidity_score < 50 THEN 'E'
      WHEN liquidity_score >= 50 AND liquidity_score < 60 THEN 'F'
      WHEN liquidity_score >= 60 AND liquidity_score < 70 THEN 'G'
      WHEN liquidity_score >= 70 AND liquidity_score < 80 THEN 'H'
      WHEN liquidity_score >= 80 AND liquidity_score < 90 THEN 'I'
      WHEN liquidity_score >= 90 AND liquidity_score < 100 THEN 'J'
      WHEN liquidity_score >= 100 THEN 'K'
      ELSE 'X'
    END AS liquidity_score_result,
    CASE
      WHEN quality_score >= 0 AND quality_score < 1 THEN 'A'
      WHEN quality_score >= 1 AND quality_score < 2 THEN 'B'
      WHEN quality_score >= 2 AND quality_score < 3 THEN 'C'
      WHEN quality_score >= 3 AND quality_score < 4 THEN 'D'
      WHEN quality_score >= 4 THEN 'E'
      ELSE 'X'
    END AS quality_score_result,
    -- 7 days
    CASE
      WHEN qt_lpv_7d_for_rent >= 0 AND qt_lpv_7d_for_rent < 5 THEN 'A'
      WHEN qt_lpv_7d_for_rent >= 5 AND qt_lpv_7d_for_rent < 10 THEN 'B'
      WHEN qt_lpv_7d_for_rent >= 10 AND qt_lpv_7d_for_rent < 20 THEN 'C'
      WHEN qt_lpv_7d_for_rent >= 20 AND qt_lpv_7d_for_rent < 30 THEN 'D'
      WHEN qt_lpv_7d_for_rent >= 30 AND qt_lpv_7d_for_rent < 40 THEN 'E'
      WHEN qt_lpv_7d_for_rent >= 40 AND qt_lpv_7d_for_rent < 50 THEN 'F'
      WHEN qt_lpv_7d_for_rent >= 50 AND qt_lpv_7d_for_rent < 60 THEN 'G'
      WHEN qt_lpv_7d_for_rent >= 60 AND qt_lpv_7d_for_rent < 70 THEN 'H'
      WHEN qt_lpv_7d_for_rent >= 70 AND qt_lpv_7d_for_rent < 80 THEN 'I'
      WHEN qt_lpv_7d_for_rent >= 80 AND qt_lpv_7d_for_rent < 90 THEN 'J'
      WHEN qt_lpv_7d_for_rent >= 90 AND qt_lpv_7d_for_rent < 100 THEN 'K'
      WHEN qt_lpv_7d_for_rent >= 100 THEN 'L'
      ELSE 'X'
    END AS lpv_7d_for_rent,
    CASE
      WHEN qt_lpv_7d_for_sale >= 0 AND qt_lpv_7d_for_sale < 5 THEN 'A'
      WHEN qt_lpv_7d_for_sale >= 5 AND qt_lpv_7d_for_sale < 10 THEN 'B'
      WHEN qt_lpv_7d_for_sale >= 10 AND qt_lpv_7d_for_sale < 20 THEN 'C'
      WHEN qt_lpv_7d_for_sale >= 20 AND qt_lpv_7d_for_sale < 30 THEN 'D'
      WHEN qt_lpv_7d_for_sale >= 30 AND qt_lpv_7d_for_sale < 40 THEN 'E'
      WHEN qt_lpv_7d_for_sale >= 40 AND qt_lpv_7d_for_sale < 50 THEN 'F'
      WHEN qt_lpv_7d_for_sale >= 50 AND qt_lpv_7d_for_sale < 60 THEN 'G'
      WHEN qt_lpv_7d_for_sale >= 60 AND qt_lpv_7d_for_sale < 70 THEN 'H'
      WHEN qt_lpv_7d_for_sale >= 70 AND qt_lpv_7d_for_sale < 80 THEN 'I'
      WHEN qt_lpv_7d_for_sale >= 80 AND qt_lpv_7d_for_sale < 90 THEN 'J'
      WHEN qt_lpv_7d_for_sale >= 90 AND qt_lpv_7d_for_sale < 100 THEN 'K'
      WHEN qt_lpv_7d_for_sale >= 100 THEN 'L'
      ELSE 'X'
    END AS lpv_7d_for_sale,
    -- 3 days
    CASE
      WHEN qt_lpv_3d_for_rent >= 0 AND qt_lpv_3d_for_rent < 5 THEN 'A'
      WHEN qt_lpv_3d_for_rent >= 5 AND qt_lpv_3d_for_rent < 10 THEN 'B'
      WHEN qt_lpv_3d_for_rent >= 10 AND qt_lpv_3d_for_rent < 20 THEN 'C'
      WHEN qt_lpv_3d_for_rent >= 20 AND qt_lpv_3d_for_rent < 30 THEN 'D'
      WHEN qt_lpv_3d_for_rent >= 30 AND qt_lpv_3d_for_rent < 40 THEN 'E'
      WHEN qt_lpv_3d_for_rent >= 40 AND qt_lpv_3d_for_rent < 50 THEN 'F'
      WHEN qt_lpv_3d_for_rent >= 50 AND qt_lpv_3d_for_rent < 60 THEN 'G'
      WHEN qt_lpv_3d_for_rent >= 60 AND qt_lpv_3d_for_rent < 70 THEN 'H'
      WHEN qt_lpv_3d_for_rent >= 70 AND qt_lpv_3d_for_rent < 80 THEN 'I'
      WHEN qt_lpv_3d_for_rent >= 80 AND qt_lpv_3d_for_rent < 90 THEN 'J'
      WHEN qt_lpv_3d_for_rent >= 90 AND qt_lpv_3d_for_rent < 100 THEN 'K'
      WHEN qt_lpv_3d_for_rent >= 100 THEN 'L'
      ELSE 'X'
    END AS lpv_3d_for_rent,
    CASE
      WHEN qt_lpv_3d_for_sale >= 0 AND qt_lpv_3d_for_sale < 5 THEN 'A'
      WHEN qt_lpv_3d_for_sale >= 5 AND qt_lpv_3d_for_sale < 10 THEN 'B'
      WHEN qt_lpv_3d_for_sale >= 10 AND qt_lpv_3d_for_sale < 20 THEN 'C'
      WHEN qt_lpv_3d_for_sale >= 20 AND qt_lpv_3d_for_sale < 30 THEN 'D'
      WHEN qt_lpv_3d_for_sale >= 30 AND qt_lpv_3d_for_sale < 40 THEN 'E'
      WHEN qt_lpv_3d_for_sale >= 40 AND qt_lpv_3d_for_sale < 50 THEN 'F'
      WHEN qt_lpv_3d_for_sale >= 50 AND qt_lpv_3d_for_sale < 60 THEN 'G'
      WHEN qt_lpv_3d_for_sale >= 60 AND qt_lpv_3d_for_sale < 70 THEN 'H'
      WHEN qt_lpv_3d_for_sale >= 70 AND qt_lpv_3d_for_sale < 80 THEN 'I'
      WHEN qt_lpv_3d_for_sale >= 80 AND qt_lpv_3d_for_sale < 90 THEN 'J'
      WHEN qt_lpv_3d_for_sale >= 90 AND qt_lpv_3d_for_sale < 100 THEN 'K'
      WHEN qt_lpv_3d_for_sale >= 100 THEN 'L'
      ELSE 'X'
    END AS lpv_3d_for_sale,
    -- 1 day
    CASE
      WHEN qt_lpv_1d_for_rent >= 0 AND qt_lpv_1d_for_rent < 5 THEN 'A'
      WHEN qt_lpv_1d_for_rent >= 5 AND qt_lpv_1d_for_rent < 10 THEN 'B'
      WHEN qt_lpv_1d_for_rent >= 10 AND qt_lpv_1d_for_rent < 20 THEN 'C'
      WHEN qt_lpv_1d_for_rent >= 20 AND qt_lpv_1d_for_rent < 30 THEN 'D'
      WHEN qt_lpv_1d_for_rent >= 30 AND qt_lpv_1d_for_rent < 40 THEN 'E'
      WHEN qt_lpv_1d_for_rent >= 40 AND qt_lpv_1d_for_rent < 50 THEN 'F'
      WHEN qt_lpv_1d_for_rent >= 50 AND qt_lpv_1d_for_rent < 60 THEN 'G'
      WHEN qt_lpv_1d_for_rent >= 60 AND qt_lpv_1d_for_rent < 70 THEN 'H'
      WHEN qt_lpv_1d_for_rent >= 70 AND qt_lpv_1d_for_rent < 80 THEN 'I'
      WHEN qt_lpv_1d_for_rent >= 80 AND qt_lpv_1d_for_rent < 90 THEN 'J'
      WHEN qt_lpv_1d_for_rent >= 90 AND qt_lpv_1d_for_rent < 100 THEN 'K'
      WHEN qt_lpv_1d_for_rent >= 100 THEN 'L'
      ELSE 'X'
    END AS lpv_1d_for_rent,
    CASE
      WHEN qt_lpv_1d_for_sale >= 0 AND qt_lpv_1d_for_sale < 5 THEN 'A'
      WHEN qt_lpv_1d_for_sale >= 5 AND qt_lpv_1d_for_sale < 10 THEN 'B'
      WHEN qt_lpv_1d_for_sale >= 10 AND qt_lpv_1d_for_sale < 20 THEN 'C'
      WHEN qt_lpv_1d_for_sale >= 20 AND qt_lpv_1d_for_sale < 30 THEN 'D'
      WHEN qt_lpv_1d_for_sale >= 30 AND qt_lpv_1d_for_sale < 40 THEN 'E'
      WHEN qt_lpv_1d_for_sale >= 40 AND qt_lpv_1d_for_sale < 50 THEN 'F'
      WHEN qt_lpv_1d_for_sale >= 50 AND qt_lpv_1d_for_sale < 60 THEN 'G'
      WHEN qt_lpv_1d_for_sale >= 60 AND qt_lpv_1d_for_sale < 70 THEN 'H'
      WHEN qt_lpv_1d_for_sale >= 70 AND qt_lpv_1d_for_sale < 80 THEN 'I'
      WHEN qt_lpv_1d_for_sale >= 80 AND qt_lpv_1d_for_sale < 90 THEN 'J'
      WHEN qt_lpv_1d_for_sale >= 90 AND qt_lpv_1d_for_sale < 100 THEN 'K'
      WHEN qt_lpv_1d_for_sale >= 100 THEN 'L'
      ELSE 'X'
    END AS lpv_1d_for_sale,
    CONCAT_WS(
      '-',
      COALESCE(listing_age, 'X'),
      COALESCE(quality_score_result, 'X'),
      COALESCE(liquidity_score_result, 'X'),
      -- COALESCE(lpv_7d_for_rent, 'X'), -- Removed at the request of SH on 2024-11-05
      -- COALESCE(lpv_7d_for_sale, 'X'), -- Removed at the request of SH on 2024-11-05
      COALESCE(lpv_3d_for_rent, 'X'),
      COALESCE(lpv_3d_for_sale, 'X')
      -- COALESCE(lpv_1d_for_rent, 'X'), -- Removed at the request of SH on 2024-11-05
      -- COALESCE(lpv_1d_for_sale, 'X') -- Removed at the request of SH on 2024-11-05
    ) AS demand_score,
    CURRENT_DATE AS dt_snapshot
  FROM for_rent_score AS fr
  FULL OUTER JOIN for_sale_score AS fs
    ON (fr.id_house = fs.id_house)
)

SELECT 
  *
FROM 
  results
GROUP BY ALL