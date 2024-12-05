WITH prospect_daily_results AS (
  SELECT DISTINCT
    pdr.id_prospect,
    pdr.id_booking,
    pdr.id_house,
    pdr.ts_event,
    pdr.event_type,
    pdr.event_name,
    pdr.business_context,
    pdr.id_region,
    ROW_NUMBER() OVER(PARTITION BY COALESCE(id_rent_flow, id_sale_flow), event_type, business_context ORDER BY ts_event ASC) AS flow_order
  FROM 
    datalake_demand_flows.prospect_daily_results AS pdr
  WHERE
    business_context = 'sale' 
), 
cte_booking AS (
  SELECT 
    pdr.id_prospect,
    pdr.id_booking,
    pdr.id_house,
    pdr.ts_event,
    pdr.event_type,
    pdr.event_name,
    pdr.business_context,
    pdr.id_region
  FROM 
    prospect_daily_results AS pdr
  WHERE 
    event_type = 'FLOW'
    AND event_name = 'VISIT BOOKED'
    AND ts_event < CURRENT_DATE()
), 
cte_bp_type AS (
  SELECT 
    pdr.id_prospect,
    pdr.event_name,
    pdr.id_region,
    CASE 
      WHEN pdr.event_name = 'USER RECOVERY' AND pdr.flow_order = 1 THEN 'RBP'
      WHEN pdr.event_name = 'USER FIRST ACTIVATION' AND pdr.flow_order = 1 THEN 'NBP'
    END AS bp_type,
    dr.city_group,
    pdr.event_type,
    pdr.ts_event AS activation_date,
    LEAD(pdr.ts_event) OVER(PARTITION BY pdr.id_prospect, dr.city_group ORDER BY pdr.ts_event ASC, pdr.event_type DESC) AS activation_end_date
  FROM 
    prospect_daily_results AS pdr
  INNER JOIN 
    datalake_region.region dr
      ON pdr.id_region = dr.id
  WHERE
    event_type = 'CONVERSION'
    AND ts_event < CURRENT_DATE()
),
 cte_bp_type_final AS (
  SELECT 
    cbt.id_prospect,
    cbt.id_region,
    cbt.bp_type,
    cbt.city_group,
    cbt.activation_date,
    cbt.activation_end_date,
    LAG(cbt.activation_date) OVER (
    PARTITION BY 
      cbt.id_prospect
    ORDER BY
      cbt.activation_date
    ) AS previous_activation_date,
    LEAD(cbt.activation_date) OVER (
      PARTITION BY cbt.id_prospect
      ORDER BY
        cbt.activation_date
    ) AS next_activation_date
  FROM 
    cte_bp_type AS cbt
  WHERE 
    cbt.bp_type is not null 
)
SELECT DISTINCT
  cbtf.id_prospect,
  cbtf.id_region,
  FIRST(cb.id_booking) OVER (PARTITION BY cbtf.id_prospect, cbtf.activation_date ORDER BY cb.ts_event ASC) AS id_first_booking,
  FIRST(cb.id_house) OVER (PARTITION BY cbtf.id_prospect, cbtf.activation_date ORDER BY cb.ts_event ASC) AS id_house_first_booking,
  cbtf.bp_type,
  cbtf.city_group,
  slpc.price_segment,
  cbtf.activation_date,
  cbtf.activation_end_date,
  FIRST(cb.ts_event) OVER (PARTITION BY cbtf.id_prospect ORDER BY cb.ts_event ASC) AS ts_first_booking,
  NOW() AS ts_load
FROM 
  cte_bp_type_final AS cbtf
LEFT JOIN
  cte_booking AS cb
    ON cbtf.id_prospect = cb.id_prospect
    AND cb.ts_event BETWEEN cbtf.activation_date AND cbtf.activation_end_date
LEFT JOIN
  datalake_sale_listings.sale_listing_price_changes AS slpc
    ON cb.id_house = slpc.id_house
    AND cb.ts_event BETWEEN slpc.ts_price_started AND COALESCE(slpc.ts_price_ended, NOW())
WHERE
  (
    cbtf.previous_activation_date IS NULL 
    OR cbtf.activation_date <> cbtf.previous_activation_date
  )
QUALIFY
  FIRST(cb.id_booking) OVER (PARTITION BY cbtf.id_prospect, cbtf.activation_date ORDER BY cb.ts_event ASC) = cb.id_booking