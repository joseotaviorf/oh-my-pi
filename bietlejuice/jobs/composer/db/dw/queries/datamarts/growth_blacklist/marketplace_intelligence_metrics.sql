WITH daily_published_listings AS (
    SELECT   
        f.sk_house_listing,
        SUBSTRING(f.sk_house_listing,1,9) AS sk_house,
        f.status_history,
        DATE(f.sk_status_start_date) AS status_start_date,
        f.status_change_reason,
        d.DATE,
        ROW_NUMBER() OVER(PARTITION BY f.sk_house_listing, d.DATE ORDER BY f.ts_status_start desc) AS order_status -- daily order status
    FROM     
        fact_house_listing_status f
    JOIN     
        dim_date d
    ON       
        d.sk_date BETWEEN NULLIF(f.sk_status_start_date,-1) 
        AND COALESCE(TO_CHAR(TO_DATE(NULLIF(sk_status_end_date, -1), 'YYYYMMDD') - 1, 'YYYYMMDD')::bigint, TO_CHAR(CURRENT_DATE -1, 'YYYYMMDD')::bigint)
    WHERE    
        SUBSTRING(sk_house_listing,10,12) <> '000' -- consider only listings that already started publication
    AND      
        d.DATE BETWEEN DATE('2019-01-01') AND CURRENT_DATE 
), 
daily_published_listings_adjusted AS (
    SELECT    
        fhs.sk_house_listing,
        fhs.sk_house,
        fhs.status_start_date,
        dhl.house_unpublished_reason,
        CASE
            WHEN fhs.status_history != 'suspenso' THEN fhs.status_history
            WHEN (
                  LOWER(fhs.status_change_reason) LIKE '%reserv%'
                  OR LOWER(fhs.status_change_reason) LIKE '%negocia%'
                  OR LOWER(fhs.status_change_reason) LIKE '%proposta%'
            ) THEN 'suspended_in_negotiation'
        ELSE 'suspended_other'
        END status_history_v2,
        dhl.house_bedrooms,
        fhs.DATE,
        fhs.order_status,
        fhs.status_history,
        fhl.sk_region
    FROM      
        daily_published_listings fhs
    LEFT JOIN 
        fact_house_listings fhl
    ON        
        fhs.sk_house_listing = fhl.sk_house_listing
    LEFT JOIN 
        dim_region dr
    ON        
        fhl.sk_region = dr.sk_region
    LEFT JOIN 
        dim_house_listing dhl
    ON        
        fhs.sk_house_listing = dhl.sk_house_listing
    WHERE     
        fhs.order_status = 1
    AND       
        dr.city_group IS NOT NULL 
), 
last_version_listings AS (
         SELECT id_house,
                sk_house_listing,
                ts_listing_version_start,
                ts_listing_version_end
         FROM   datalake_clean.ods_dim_house_listing
         WHERE  VERSION > 0 
), 
events AS (
    SELECT    
        DATE(ts_event) AS event_date,
        ts_event AS event_timestamp,
        ev.id_user,
        lvl.sk_house_listing,
        CASE
            WHEN TRIM(event_type) = 'listing_page_viewed' THEN 1
            ELSE 0
        END AS listing_page_viewed,
        CASE
            WHEN TRIM(event_type) = 'piloto_cw_message_sent' THEN 1
            ELSE 0
        END AS talk_to_agent_message_sent,
        CASE
            WHEN TRIM(event_type) = 'offer_submitted' THEN 1
            ELSE 0
        END AS offer_submitted,
        CASE
            WHEN TRIM(event_type) = 'visit_schedule_confirmed' THEN 1
            ELSE 0
        END AS visit_booked,
        CASE
            WHEN TRIM(event_type) = 'contract_docusign_signed' THEN 1
            ELSE 0
        END AS contract_signed
    FROM      
        datalake_amplitude_clean_prod.events ev
    LEFT JOIN 
        last_version_listings lvl
    ON        
        TRIM(JSON_EXTRACT_PATH_TEXT(ev.event_properties, 'house_id')) = lvl.id_house
    AND       
        ev.ts_event BETWEEN lvl.ts_listing_version_start AND (COALESCE(lvl.ts_listing_version_end, CURRENT_TIMESTAMP) - interval '1 second')
    WHERE  
        DATE(ev.ts_event) >= DATE('2019-01-01')
        AND TO_DATE(ev.year::varchar || ev.month::varchar || ev.day::varchar,'YYYYMMDD') >= DATE('2018-06-01')
        AND TRIM(ev.event_type) IN ('listing_page_viewed',
                                    'piloto_cw_message_sent',
                                    'offer_submitted',
                                    'visit_schedule_confirmed',
                                    'contract_docusign_signed') 
)
SELECT    
    dpl.DATE AS base_date,
    dpl.sk_house_listing,
    dpl.sk_house,
    dpl.house_bedrooms,
    datediff(week, dpl.status_start_date, dpl.DATE) AS age_weeks,
    dpl.status_start_date AS publication_date,
    dpl.house_unpublished_reason,
    dpl.sk_region,
    dpl.status_history,
    dpl.status_history_v2,
    evt.id_user,
    coalesce(sum(evt.listing_page_viewed), 0) AS listing_page_viewed,
    coalesce(sum(evt.talk_to_agent_message_sent), 0) AS talk_to_agent_message_sent,
    coalesce(sum(evt.offer_submitted), 0) AS offer_submitted,
    coalesce(sum(evt.visit_booked), 0) AS visit_booked,
    coalesce(sum(evt.contract_signed), 0) AS contract_signed
FROM      
    daily_published_listings_adjusted dpl
LEFT JOIN 
    events evt
ON        
    dpl.sk_house_listing = evt.sk_house_listing
    AND dpl.DATE = evt.event_date
GROUP BY  
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11