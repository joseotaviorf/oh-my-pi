/*
This table will use the threshold information generated in the thresholds table.
It will run daily to track the status of listings with respect to being stranded or not.
*/
WITH visits AS (
/* We will track every visit of the sale listings */
    SELECT DISTINCT
        id_house,
        COALESCE(BIGINT(DATE_FORMAT(ts_created, 'yyyyMMdd')), -1) AS id_booking_created_date
    FROM 
        datalake_booking.booking
    WHERE 
        visit_intent = 'SALE'
        AND ts_created IS NOT NULL
),
offers AS (
/* We will track every offer of the sale listings */
    SELECT DISTINCT 
        id_house,
        COALESCE(BIGINT(DATE_FORMAT(ts_offer_submitted, 'yyyyMMdd')), -1) AS id_offer_submitted_date
    FROM 
        datalake_offer.sale_offer
    WHERE 
        ts_offer_submitted IS NOT NULL
),
fact_listing_status AS (
/* We will track every visit of the sale listings */
    SELECT
        l.id_sale_listing,
        l.id_house,
        l.id_region,
        COALESCE(BIGINT(DATE_FORMAT(l.ts_status_started, 'yyyyMMdd')), -1) AS id_status_start_date,
        COALESCE(BIGINT(DATE_FORMAT(l.ts_status_ended, 'yyyyMMdd')), -1) AS id_status_end_date,
        BIGINT(DATE_FORMAT(l.ts_first_publication, 'yyyyMMdd')) AS id_first_publication_date,
        CASE 
            WHEN h.sale_price IS NULL OR h.sale_price < 150000 THEN NULL
            WHEN h.sale_price < 300000 THEN '150-300k'
            WHEN h.sale_price < 500000 THEN '300-500k'
            WHEN h.sale_price < 900000 THEN '500-900k'
            WHEN h.sale_price < 1500000 THEN '900-1500k'
            WHEN h.sale_price >= 1500000  THEN '1500k+'
        END AS bedrooms_price_bins,
        CASE 
            WHEN r.city_group = 'RMSP' THEN 'RMSP'
            WHEN r.city_group = 'Rio de Janeiro' THEN 'Rio de Janeiro'
            WHEN r.city_group = 'Porto Alegre' THEN 'Porto Alegre'
            ELSE 'Other City Group'
        END AS city_group,
        l.ts_status_started
    FROM 
        datalake_sale_listings.sale_listing_status AS l
    LEFT JOIN 
        datalake_ebdb_listing.house AS h 
            ON BIGINT(LEFT(l.id_sale_listing, 9)) = h.id
    LEFT JOIN 
        datalake_region.region AS r 
            ON l.id_region = r.id
            AND r.level IN ('SubRegiao', 'Cidade')
    WHERE 
        l.status_history = 'PUBLISHED' 
),
ongoing_listings AS (
/*
With the visits and offers, we will do the ongoing listings to understand the amount of days in publication each listing has. 
In addition, we group into price bins and region
*/
    SELECT
        f.id_sale_listing,
        f.id_house,
        f.id_region,
        d.id_date,
        f.id_first_publication_date,
        v.id_booking_created_date AS visits, 
        o.id_offer_submitted_date AS offers,
        f.bedrooms_price_bins,
        f.city_group,
        LAST_VALUE(v.id_booking_created_date, TRUE) OVER (PARTITION BY f.id_house ORDER BY date) AS lag_visits,
        LAST_VALUE(o.id_offer_submitted_date, TRUE) OVER (PARTITION BY f.id_house ORDER BY date) AS lag_offers,
        MIN(v.id_booking_created_date) OVER (PARTITION BY f.id_sale_listing) AS first_visit,
        MIN(o.id_offer_submitted_date) OVER (PARTITION BY f.id_sale_listing) AS first_offer,
        COUNT(d.id_date) OVER (PARTITION BY f.id_sale_listing) AS days_published,
        ROW_NUMBER() OVER (PARTITION BY f.id_sale_listing ORDER BY d.date ASC) AS ongoing_days_published,
        d.date,
        d.month_start
    FROM 
        fact_listing_status AS f
    JOIN 
        datalake_quintoandar.aux_date AS d
            ON d.id_date BETWEEN NULLIF(f.id_status_start_date,-1) 
            AND COALESCE(NULLIF(f.id_status_end_date, -1), CAST(REPLACE(CAST(CURRENT_DATE AS STRING), '-', '') AS BIGINT) - 1)
            AND d.date <= DATE_SUB(CURRENT_DATE, 1)
    LEFT JOIN 
        datalake_ebdb_listing.house AS h 
            ON BIGINT(LEFT(f.id_sale_listing, 9)) = h.id
    LEFT JOIN 
        visits AS v 
            ON h.id = v.id_house
            AND d.id_date = v.id_booking_created_date
    LEFT JOIN 
        offers AS o 
            ON h.id = o.id_house
            AND d.id_date = o.id_offer_submitted_date
    QUALIFY 
        ROW_NUMBER() OVER (PARTITION BY f.id_sale_listing, d.date ORDER BY f.ts_status_started DESC) = 1
),
stranded_logic AS (
/*
In this CTE, we import all thresholds present in the other table, 
as well as apply logic to check which listings are stranded in each category.
*/
    SELECT 
        ol.id_sale_listing,
        ol.id_house,
        ol.id_region,
        ol.id_first_publication_date,
        ol.id_date, 
        ol.ongoing_days_published,
        CASE
            WHEN ol.first_visit IS NULL AND ol.ongoing_days_published >= t.threshold_first_visit THEN TRUE
            WHEN ol.first_visit IS NOT NULL AND ol.id_date < ol.first_visit AND ol.ongoing_days_published >= t.threshold_first_visit THEN TRUE
            ELSE false
        END AS visit_stranded_check,
        CASE
            WHEN ol.first_offer IS NULL AND ol.ongoing_days_published >= t.threshold_first_offer THEN TRUE
            WHEN ol.first_offer IS NOT NULL AND ol.id_date < ol.first_offer AND ol.ongoing_days_published >= t.threshold_first_offer THEN TRUE
            ELSE false
        END AS offer_stranded_check,
        CASE
            WHEN ol.first_visit IS NOT NULL AND DATEDIFF(date, TO_DATE(CAST(ol.lag_visits AS STRING), 'yyyyMMdd')) >= t.threshold_recurrence_visit THEN TRUE
            ELSE FALSE
        END AS visit_stranded_recurrence_check,
        CASE
            WHEN ol.first_offer IS NOT NULL AND DATEDIFF(date, TO_DATE(CAST(ol.lag_offers AS STRING), 'yyyyMMdd')) >= t.threshold_recurrence_offer THEN TRUE
            ELSE FALSE
        END AS offer_stranded_recurrence_check
    FROM 
        ongoing_listings AS ol
    LEFT JOIN 
        datalake_sale_stranded_listings.thresholds AS t
            ON ol.bedrooms_price_bins = t.bedrooms_price_bins
            AND ol.city_group = t.city_group
            AND ol.month_start = t.month_start
    QUALIFY 
        MAX(t.month_start) OVER (PARTITION BY 1) >= ol.month_start
),
apply_hierarchy AS (
/*
Since we have checked which strandeds each listing is in, we will now apply the hierarchy. 
(E. g.: A listing that is offer stranded and also visit stranded, will be offer stranded, 
since it takes a longer time to become offer stranded and thus, occupies a more critical status.)
*/
    SELECT 
        id_sale_listing,
        id_house,
        id_region,
        id_first_publication_date,
        id_date, 
        CASE 
            WHEN offer_stranded_recurrence_check THEN 'RECURRENCE_OFFER_STRANDED'
            WHEN offer_stranded_check THEN 'OFFER_STRANDED'
            WHEN visit_stranded_recurrence_check AND NOT(offer_stranded_recurrence_check)THEN 'RECURRENCE_VISIT_STRANDED'
            WHEN visit_stranded_check AND NOT(offer_stranded_check) THEN 'VISIT_STRANDED'
            ELSE 'HEALTH_LISTING'
        END AS stranded_status,
        ongoing_days_published,
        offer_stranded_check AND visit_stranded_check AS is_offer_and_visit_stranded
    FROM 
        stranded_logic
),
status_changes AS (
/*
CTE that will help create the status change columns for each listing
*/
    SELECT 
        id_sale_listing,
        id_house,
        id_region,
        id_first_publication_date,
        id_date, 
        stranded_status,
        ongoing_days_published AS days_published,
        is_offer_and_visit_stranded
    FROM 
        apply_hierarchy
    QUALIFY 
        LEAD(stranded_status) OVER (PARTITION BY id_sale_listing ORDER BY id_date DESC) <> stranded_status
        OR ROW_NUMBER() OVER (PARTITION BY id_sale_listing ORDER BY id_date ASC) = 1 
),
aux AS (
    SELECT 
        id_sale_listing,
        id_house,
        id_region,
        id_first_publication_date,
        id_date AS id_started_date,
        LAG(id_date) OVER (PARTITION BY id_sale_listing ORDER BY id_date DESC) AS id_ended_date,
        stranded_status,
        days_published,
        is_offer_and_visit_stranded,
        ROW_NUMBER() OVER (PARTITION BY id_sale_listing ORDER BY id_date DESC) = 1 AS is_last_status
    FROM
        status_changes
)
SELECT 
    id_sale_listing,
    id_house,
    id_region,
    id_first_publication_date,
    id_started_date,
    id_ended_date,
    stranded_status,
    days_published,
    is_offer_and_visit_stranded,
    is_last_status,
    TO_DATE(CAST(id_started_date AS STRING), 'yyyyMMdd') AS dt_status_started,
    TO_DATE(CAST(NULLIF(id_ended_date, -1) AS STRING), 'yyyyMMdd') AS dt_status_ended
FROM
    aux