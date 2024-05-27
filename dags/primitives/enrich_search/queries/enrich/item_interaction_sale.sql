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
      LOWER(ss.business_context) = 'sale'
      AND ss.search_rendering_type != "N/A"
      AND ss.event_type = 'Search'
      AND ss.year >= 2022
  GROUP BY 1,2,3
),

sale_flow AS (
  SELECT
    sale_flow.id_house,
    sale_flow.id_buyer,
    MIN(sale_flow.ts_first_event) AS ts_first_event
  FROM
    datalake_sale_flows.sale_flow
  WHERE
    sale_flow.ts_first_event >= '2022-01-01'
    AND sale_flow.flow_type IN (
      'VB', -- The buyer only booked visits
      'VB_VC', -- The buyer performed visits 
      'VB_VC_OS', -- The buyer performed visits and made an offer
      'VB_OS', -- The buyer booked visits and made an offer
      'OS' -- The buyer only performed offers
    )
  GROUP BY
    1, 2
),

sale_flow_target AS (
    SELECT
        search.id_search AS id_search,
        sale_flow.id_buyer AS id_user,
        sale_flow.id_house AS id_item,
        'sale_flow' AS interaction_type,
        search.search_rendering_type AS search_rendering_type,
        'house' AS type_item,
        sale_flow.ts_first_event AS ts_interaction,
        search.ts_event AS ts_search,
        DATE(sale_flow.ts_first_event) AS dt_interaction,
        "sale" AS business_context,
        year(sale_flow.ts_first_event) AS year,
        month(sale_flow.ts_first_event) AS month,
        day(sale_flow.ts_first_event) AS day
    FROM  
       sale_flow
    LEFT JOIN 
       user_to_main_amp u2a
       ON 
          u2a.id_user = sale_flow.id_buyer
    INNER JOIN 
       search_event AS search 
       ON 
          search.id_amplitude_main = u2a.id_amplitude_main
        AND sale_flow.id_house = search.id_house
        AND DATE(search.ts_event) >= DATE_SUB(DATE(sale_flow.ts_first_event), {days_past})
        AND search.ts_event <= sale_flow.ts_first_event 
)

SELECT * from sale_flow_target