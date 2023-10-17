WITH first_sale_flows AS (
    SELECT
        id_house,
        MIN(ts_first_event) AS ts_first_sale_flow,
        MIN(ts_first_booking_created) AS ts_first_booking,
        MIN(dt_sale_agreement_signed) AS dt_first_sale_agreement_signed,
        MIN(dt_house_registry_ended) AS dt_house_registry_ended,
        MIN(ts_first_offer_submitted) AS ts_first_offer_submitted,
        MIN(ts_first_visit_completed) AS ts_first_visit_completed,
        MIN(dt_first_offer_accepted) AS dt_first_offer_accepted,
        COUNT(ts_first_visit_completed) AS total_listings_visit_completed,
        COUNT(ts_first_offer_submitted) AS total_listings_offer_submited,
        COUNT(dt_first_offer_accepted) AS total_listings_offer_accepted
    FROM
        datalake_sale_flows.sale_flow
    GROUP BY 1
)
SELECT
    sl.id_sale_listing,
    sl.id_house,
    DATEDIFF(sf.ts_first_sale_flow, sl.ts_first_publication) AS days_first_publication_to_first_sale_flow,
    DATEDIFF(sf.ts_first_booking, sl.ts_first_publication) AS days_first_publication_to_first_booking,
    DATEDIFF(sf.ts_first_visit_completed, sl.ts_first_publication) AS days_first_publication_to_visit_completed,     
    DATEDIFF(sf.ts_first_offer_submitted, sl.ts_first_publication) AS days_first_publication_to_first_offer_submitted,  
    DATEDIFF(sf.dt_first_offer_accepted, sl.ts_first_publication) AS days_first_publication_to_first_offer_accepted,
    DATEDIFF(sf.dt_first_sale_agreement_signed, sl.ts_first_publication) AS days_first_publication_to_first_sale_agreement_signed,
    DATEDIFF(sf.dt_house_registry_ended, sl.ts_first_publication) AS days_first_publication_to_house_registry_ended,
    DATEDIFF(sf.ts_first_visit_completed, sf.ts_first_booking) AS days_first_booking_to_first_visit_completed,
    DATEDIFF(sf.ts_first_offer_submitted, sf.ts_first_visit_completed) AS days_first_visit_completed_to_first_offer_submitted,
    DATEDIFF(sf.dt_first_offer_accepted, sf.ts_first_offer_submitted) AS days_first_offer_submitted_to_first_offer_accepted,
    DATEDIFF(sf.dt_first_sale_agreement_signed, sf.ts_first_offer_submitted) AS days_first_offer_accepted_to_first_sale_agreement_signed,
    COALESCE(sf.total_listings_visit_completed, 0) AS total_listings_visit_completed,
    COALESCE(sf.total_listings_offer_submited, 0) AS total_listings_offer_submited,
    COALESCE(sf.total_listings_offer_accepted, 0) AS total_listings_offer_accepted,  
    sf.ts_first_sale_flow,
    sf.ts_first_booking,
    sf.ts_first_visit_completed,  
    sf.ts_first_offer_submitted,
    sf.dt_first_offer_accepted,
    sf.dt_first_sale_agreement_signed,
    sf.dt_house_registry_ended
FROM
    datalake_sale_listings.sale_listing AS sl
LEFT JOIN
    first_sale_flows AS sf
        ON sf.id_house = sl.id_house
