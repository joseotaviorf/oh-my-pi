----------------
-- Rent Outlier Users have on of the conditions below:
-- 1 - More than 20 visits booked in the past 30 days
-- 2 - More than 20 offers submitted in the past 30 days

-- These values were obtained by 1) looking at the current distribution and 2) somewhat intuition into what "normal" users can do

WITH rent_user_metrics AS (
    SELECT
        id_tenant_prospect as id_user,
        COUNT(DISTINCT CASE WHEN ts_booking_created is not null THEN id_house END) as total_bookings,
        COUNT(DISTINCT CASE WHEN ts_offer_submitted is not null THEN id_house END) as total_offers
    FROM
        datalake_rent_flows.rent_flows
    WHERE
        id_tenant_prospect IS NOT NULL
        AND id_house IS NOT NULL
        AND
            (
             ts_booking_created BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
             OR
             ts_offer_submitted BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
            )
    GROUP BY
        id_tenant_prospect
)
SELECT id_user, total_bookings, total_offers
FROM rent_user_metrics
WHERE total_bookings >= 20 OR total_offers >= 20
