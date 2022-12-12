/*
This table refers to the thresholds generated monthly, where the results will be used in the stranded_status table.
We did not put any internal dependencies on it so that it could be skipped daily and only run on the first day of each month.
*/
WITH visits AS (
/* We will track every visit of the sale listings */
    SELECT DISTINCT
        id_house,
        COALESCE(BIGINT(DATE_FORMAT(ts_created, 'yyyyMMdd')), -1) AS sk_booking_created_date
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
        COALESCE(BIGINT(DATE_FORMAT(ts_offer_submitted, 'yyyyMMdd')), -1) AS sk_offer_submitted_date
    FROM 
        datalake_offer.sale_offer
    WHERE 
        ts_offer_submitted IS NOT NULL
),
fact_listing_status AS (
/* We will track every visit of the sale listings */
    SELECT
        id_sale_listing,
        id_region,
        COALESCE(BIGINT(DATE_FORMAT(ts_status_started, 'yyyyMMdd')), -1) AS sk_status_start_date,
        COALESCE(BIGINT(DATE_FORMAT(ts_status_ended, 'yyyyMMdd')), -1) AS sk_status_end_date,
        ts_status_started,
        status_history
    FROM 
        datalake_sale_listings.sale_listing_status
),
ongoing_listings AS (
/*
With the visits and offers, we will do the ongoing listings to understand the amount of days in publication each listing has. 
In addition, we group into price bins and region
*/
    SELECT
        f.id_sale_listing,
        d.id_date,
        f.status_history,
        CASE 
            WHEN r.city_group = 'RMSP' THEN 'RMSP'
            WHEN r.city_group = 'Rio de Janeiro' THEN 'Rio de Janeiro'
            WHEN r.city_group = 'Porto Alegre' THEN 'Porto Alegre'
            ELSE 'Other City Group'
        END AS city_group,
        CASE 
            WHEN h.sale_price IS NULL OR h.sale_price < 150000 THEN NULL
            WHEN h.sale_price < 300000 THEN '150-300k'
            WHEN h.sale_price < 500000 THEN '300-500k'
            WHEN h.sale_price < 900000 THEN '500-900k'
            WHEN h.sale_price < 1500000 THEN '900-1500k'
            WHEN h.sale_price >= 1500000  THEN '1500k+'
        END AS bedrooms_price_bins,
        CASE
            WHEN h.sale_price < 300000 THEN 1
            WHEN h.sale_price < 500000 THEN 2
            WHEN h.sale_price < 900000 THEN 3
            WHEN h.sale_price < 1500000 THEN 4
            WHEN h.sale_price >= 1500000 THEN 5
        END AS bins_order,
        v.sk_booking_created_date AS visits, 
        o.sk_offer_submitted_date AS offers,
        MIN(v.sk_booking_created_date) OVER (PARTITION BY f.id_sale_listing) AS first_visit,
        MIN(o.sk_offer_submitted_date) OVER (PARTITION BY f.id_sale_listing) AS first_offer,
        COUNT(d.id_date) OVER (PARTITION BY f.id_sale_listing) AS days_published,
        ROW_NUMBER() OVER (PARTITION BY f.id_sale_listing ORDER BY d.date ASC) AS ongoing_days_published,
        d.date,
        d.month_start
    FROM 
        fact_listing_status AS f
    JOIN 
        datalake_quintoandar.aux_date AS d
            ON d.id_date BETWEEN NULLIF(f.sk_status_start_date,-1) 
            AND COALESCE(NULLIF(f.sk_status_end_date, -1), CAST(REPLACE(CAST(CURRENT_DATE AS STRING), '-', '') AS BIGINT) - 1)
            AND d.date <= DATE_SUB(CURRENT_DATE, 1)
    LEFT JOIN 
        datalake_ebdb_listing.house AS h 
            ON BIGINT(LEFT(f.id_sale_listing, 9)) = h.id
    LEFT JOIN 
        visits AS v 
            ON h.id = v.id_house
            AND d.id_date = v.sk_booking_created_date
    LEFT JOIN 
        offers AS o 
            ON h.id = o.id_house
            AND d.id_date = o.sk_offer_submitted_date
    LEFT JOIN 
        datalake_region.region AS r 
            ON f.id_region = r.id
            AND r.level IN ('SubRegiao', 'Cidade')
    WHERE 
        1 = 1 
        AND f.status_history = 'PUBLISHED' 
    QUALIFY 
        ROW_NUMBER() OVER (PARTITION BY f.id_sale_listing, d.date ORDER BY f.ts_status_started DESC) = 1
),
days_published_ongoing_listings_check AS (
/*
This is to help us calculate how many days in publication the listing was on each visit or offer
*/    
    SELECT 
        id_sale_listing,
        id_date,
        status_history,
        city_group,
        bedrooms_price_bins,
        bins_order,
        days_published,
        ongoing_days_published,
        CASE 
            WHEN id_date = first_visit THEN ongoing_days_published 
            ELSE NULL 
        END AS days_published_to_first_visit,
        CASE 
            WHEN id_date = first_offer THEN ongoing_days_published 
            ELSE NULL 
        END AS days_published_to_first_offer,
        month_start
    FROM 
        ongoing_listings
),
first_event AS (
/*
For first event stranded, we will extract the number of days in publication that the listing was in this event
*/
  SELECT
        month_start, 
        id_sale_listing,
        bedrooms_price_bins, 
        bins_order,
        city_group,
        bedrooms_price_bins,
        MIN(days_published_to_first_visit) AS days_published_to_first_visit,
        MIN(days_published_to_first_offer) AS days_published_to_first_offer
    FROM 
        days_published_ongoing_listings_check
    GROUP BY 
        1, 2, 3, 4, 5
),
days_published_ongoing_listings_for_recurrence_check AS (
/*
Now for recurrence stranded, we need to calculate the difference in days between visits and offers for each listing.
This CTE helps identify with how many days in publishing between each listing event.
(E. g.: If he had 15 days of published on the first visit, 40 days passed, he would have 65 days of published, 
but 15 days until the first visit and 40 days until the second visit. With these last two numbers, we will calculate the metric)
*/
    SELECT 
        id_sale_listing,
        id_date,
        status_history,
        city_group,
        bedrooms_price_bins,
        bins_order,
        days_published,
        ongoing_days_published,
        IF(id_date = visits AND status_history = 'PUBLISHED', ROW_NUMBER() OVER (PARTITION BY id_sale_listing, status_history ORDER BY date ASC), NULL) AS days_published_to_visits,
        IF(id_date = offers AND status_history = 'PUBLISHED', ROW_NUMBER() OVER (PARTITION BY id_sale_listing, status_history ORDER BY date ASC), NULL) AS days_published_to_offers,
        month_start
    FROM 
        ongoing_listings
),
days_between_events AS (
/*
This CTE helps to fill the column, where we will later need it filled in to apply a lag and understand the time difference between dates
*/
    SELECT 
        month_start, 
        id_sale_listing,
        days_published_to_visits AS check,
        LAST(days_published_to_visits, TRUE) OVER (PARTITION BY id_sale_listing ORDER BY id_date) AS days_published_to_visits,
        LAST(days_published_to_offers, TRUE) OVER (PARTITION BY id_sale_listing ORDER BY id_date) AS days_published_to_offers
    FROM 
        days_published_ongoing_listings_for_recurrence_check
),
lag_days_between_events AS (
/*
We apply lag to extract the difference between dates
*/
    SELECT 
        month_start, 
        id_sale_listing,
        check,
        NULLIF(days_published_to_visits - LAG(days_published_to_visits) OVER (PARTITION BY id_sale_listing ORDER BY days_published_to_visits), 0) AS diff_days_between_visits,
        NULLIF(days_published_to_offers - LAG(days_published_to_offers) OVER (PARTITION BY id_sale_listing ORDER BY days_published_to_offers), 0) AS diff_days_between_offers
    FROM 
        days_between_events
),
recurrence_by_month AS (
/*
Here we apply the average for the month of the difference in days between events. 
(E.g.: In the same month they had two visits, adding up to 3 total visits from the listing. 
Between visit 1 and 2 you had a difference of 40 published days, between visit 2 and 3 you had only 10 days (both occurring in the same month). 
So for that month, we have an average day difference equal to 25.)
*/
    SELECT 
        month_start, 
        id_sale_listing,
        ROUND(AVG(diff_days_between_visits)) AS avg_days_between_visits,
        ROUND(AVG(diff_days_between_offers)) AS avg_days_between_offers
    FROM
        lag_days_between_events
    GROUP BY 
        1, 2
),
recurrence AS (
/*
This CTE will take all the monthly averages and make a moving average, where each following month will be included in the average of all the previous months
*/
    SELECT 
        month_start, 
        id_sale_listing,
        ROUND(AVG(avg_days_between_visits) OVER (PARTITION BY id_sale_listing ORDER BY month_start ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)) AS avg_days_between_visits,
        ROUND(AVG(avg_days_between_offers) OVER (PARTITION BY id_sale_listing ORDER BY month_start ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)) AS avg_days_between_offers
    FROM 
        recurrence_by_month
),
aux AS (
/* Aggregating all metrics and taking the 90% percentile (business rule) for each metric */
    SELECT 
        month_start,
        city_group, 
        bedrooms_price_bins,
        bins_order,
        COUNT(DISTINCT id_sale_listing) AS listings,
        ROUND(PERCENTILE(days_published_to_first_visit, 0.90)) AS threshold_first_visit,
        ROUND(PERCENTILE(days_published_to_first_offer, 0.90)) AS threshold_first_offer,
        ROUND(PERCENTILE(avg_days_between_visits, 0.90)) AS threshold_recurrence_visit,
        ROUND(PERCENTILE(avg_days_between_offers, 0.90)) AS threshold_recurrence_offer
    FROM
        first_event AS f
    LEFT JOIN 
        recurrence AS r
            USING(month_start, id_sale_listing)
    WHERE 
        bedrooms_price_bins IS NOT NULL 
    GROUP BY 
        1, 2, 3, 4
)
SELECT
    month_start,
    city_group, 
    bedrooms_price_bins,
    bins_order,
    listings,
    threshold_first_visit,
    threshold_first_offer,
    threshold_recurrence_visit,
    threshold_recurrence_offer,
    MONTH(month_start) AS month,
    YEAR(month_start) AS year
FROM 
    aux
WHERE 
    YEAR(month_start) = {year}
    AND MONTH(month_start) = {month}
