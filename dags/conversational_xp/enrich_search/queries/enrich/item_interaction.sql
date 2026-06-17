WITH user_to_main_amp AS (
    SELECT
        id_user,
        MAX(id_amplitude_main) as id_amplitude_main
    
    FROM 
       datalake_search.amplitude_user_device

    WHERE 
       id_user is not null
    GROUP BY 1
),

amp_to_main_amp AS (
    SELECT
        id_amplitude,
        MAX(id_amplitude_main) as id_amplitude_main
    FROM 
       datalake_search.amplitude_user_device
    WHERE 
       id_amplitude is not null
    GROUP BY 1
),

search_event AS (
  SELECT
      a2a.id_amplitude_main,
      ss.id_house,
      ss.id_search,
      MAX(ss.search_rendering_type) as search_rendering_type,
      MIN(ss.ts_event) as ts_event,
      MIN(ss.id_amplitude) as id_amplitude
  FROM 
     datalake_search_session_event.search_session_event ss

  LEFT JOIN 
     amp_to_main_amp a2a
     ON 
        a2a.id_amplitude = ss.id_amplitude
  WHERE
      LOWER(ss.business_context) = 'rent'
      AND ss.search_rendering_type != "N/A"
      AND ss.event_type = 'Search'
      -- Fact scan bounded to the reprocess window + the {days_past} lookback.
      -- search_session_event is partitioned by (year, month, day) derived from the
      -- event date, so filter on MAKE_DATE(year, month, day) for day-level partition
      -- pruning. A year-only predicate would scan every month/day in those years.
      AND MAKE_DATE(ss.year, ss.month, ss.day)
            BETWEEN DATE_SUB(DATE('{start_date}'), {days_reprocess} + {days_past})
                AND DATE('{end_date}')
  GROUP BY 1,2,3


),

valid_offers AS (
    SELECT 
        min_by(id_rent_flow, ts_created) as id_rent_flow
    FROM 
       datalake_ebdb_clean.offer
    WHERE 
       (offer.original_rent - offer.rent)/ offer.original_rent  <= 0.1
    GROUP BY id_client, id_house
),

unique_valid_offers AS (
    SELECT
        rent_flow.id_house,
        rent_flow.id_tenant_prospect,
        MIN(rent_flow.ts_created) as ts_created
    FROM  
       datalake_rent_flows.rent_flows AS rent_flow
    INNER JOIN  
       valid_offers AS voffer 
       ON 
          rent_flow.id_rent_flow = voffer.id_rent_flow
    WHERE 
       -- Flow fact bounded to the reprocess window. rent_flows is partitioned by
       -- country_code only (no date partitions), so this ts_created predicate is a
       -- data filter, not partition pruning - it still caps the rows fed into the join.
       rent_flow.ts_created >= DATE_SUB(DATE('{start_date}'), {days_reprocess})
       AND rent_flow.ts_created < DATE_ADD(DATE('{end_date}'), 1)
    GROUP BY 1,2

),

proper_offer_target AS (
    SELECT
        search.id_search AS id_search,
        rent_flow.id_tenant_prospect AS id_user,
        rent_flow.id_house AS id_item,
        'proper_offer' AS interaction_type,
        search.search_rendering_type AS search_rendering_type,
        'house' AS type_item,
        rent_flow.ts_created AS ts_interaction,
        search.ts_event AS ts_search,
        DATE(rent_flow.ts_created) AS dt_interaction,
        "rent" AS business_context,
        year(rent_flow.ts_created) AS year,
        month(rent_flow.ts_created) AS month,
        day(rent_flow.ts_created) AS day
    FROM  
       unique_valid_offers AS rent_flow
    LEFT JOIN 
       user_to_main_amp u2a
       ON 
          u2a.id_user = rent_flow.id_tenant_prospect
    INNER JOIN 
       search_event AS search 
       ON 
          search.id_amplitude_main = u2a.id_amplitude_main
        AND rent_flow.id_house = search.id_house
        AND DATE(search.ts_event) >= DATE_SUB(DATE(rent_flow.ts_created), {days_past})
        AND search.ts_event <= rent_flow.ts_created 
)


SELECT
    id_user,
    id_item,
    interaction_type,
    id_search,
    search_rendering_type,
    type_item,
    ts_interaction,
    ts_search,
    dt_interaction,
    business_context,
    year,
    month,
    day
FROM proper_offer_target