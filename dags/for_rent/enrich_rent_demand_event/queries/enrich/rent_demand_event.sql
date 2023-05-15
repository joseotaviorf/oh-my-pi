WITH rent_flow_house_listing AS (
  SELECT 
    rf.id_rent_flow,
    rf.id_user_agent,
    rf.id_contract,
    COALESCE(
      CAST(
        rf.id_house ||
        LPAD(
        COALESCE(
          CAST(COALESCE(hl_contract.version, hl.version) AS VARCHAR(3)),'1'),3,'0') AS BIGINT), CAST(-1 AS BIGINT)
    ) AS id_house_listing,
    h.id_region,
    h.id_user,
    rf.id_booking,   
    rf.id_offer_context AS id_offer,
    rf.id_proposal,
    COALESCE(h.country_code, 'Undefined') AS country_code
  FROM
    datalake_ebdb_rent_flow.rent_flow AS rf
  JOIN
    datalake_ebdb_listing.house_listing AS hl
      ON hl.id_house = rf.id_house
      AND COALESCE(rf.dt_rent_flow_created, '1900-01-01') BETWEEN COALESCE(hl.ts_listing_version_start, '1900-01-01')
        AND COALESCE(hl.ts_listing_version_end, NOW())
  LEFT JOIN
    datalake_ebdb_listing.house AS h
      ON hl.id_house = h.id
  LEFT JOIN
    datalake_ebdb_clean.contract AS con
      ON con.id_house = rf.id_house
      AND con.id = rf.id_contract
  LEFT JOIN
    datalake_ebdb_listing.house_listing AS hl_contract
      ON con.id_house = hl_contract.id_house 
      AND con.ts_created BETWEEN COALESCE(hl_contract.ts_listing_version_start, '2000-01-01 00:00:00') 
        AND COALESCE(hl_contract.ts_listing_version_end, CURRENT_DATE)
  LEFT JOIN
    datalake_booking.booking AS bk
      ON bk.id = rf.id_booking  
  LEFT JOIN
    datalake_ebdb_listing.listing_business_context AS lbc
      ON lbc.id_house = h.id
  WHERE 
    (lbc.business_context = 'RENT'
    OR lbc.business_context IS NULL) -- Some properties exists on the House table but not on LBC. In order to keep the same rule/results
      -- that we have on the fact_listing_rent_flows, we decided to add another filter considering the business context as null
    AND (
      COALESCE(bk.visit_intent, '') <> 'SALE'
      OR (
        bk.visit_intent = 'SALE'
        AND rf.id_contract IS NOT NULL
      )
    )
),
rent_demand_events AS (                                                                  
  SELECT --visits_booked
    bk.id AS id_event,
    bk.id AS id_booking,
    rf.id_offer,
    rf.id_proposal,
    rf.id_contract,                                                                          
    1 AS id_event_type,                                                                                  
    bk.id_visitor AS id_client,                                                                      
    bk.id_house,                                                                        
    bk.id_agent AS id_user_agent,                                                                        
    bk.id_rent_flow,                                                                    
    bk.ts_created AS ts_event,                                                                      
    rf.id_house_listing,                                                                
    rf.id_region,                                                                       
    rf.id_user,                                                                         
    rf.country_code,
    YEAR(ts_created) AS year,
    MONTH(ts_created) AS month,
    DAY(ts_created) AS day
  FROM
    datalake_booking.booking AS bk
  JOIN
    rent_flow_house_listing AS rf
      ON rf.id_booking = bk.id
  WHERE 
    bk.type = 'Visita'
    AND bk.ts_created IS NOT NULL
    AND YEAR(ts_created) = {year} 
    AND MONTH(ts_created) = {month} 
    AND DAY(ts_created) = {day}
  UNION ALL
  SELECT --visits_completed 
    bk.id AS id_event,
    bk.id AS id_booking,
    rf.id_offer,
    rf.id_proposal,
    rf.id_contract,                                                                           
    2 AS id_event_type,                                                                                   
    bk.id_visitor AS id_client,                                                                       
    bk.id_house,                                                                        
    bk.id_agent AS id_user_agent,                                                                        
    bk.id_rent_flow,                                                                    
    bk.dt_booking AS ts_event,                                                                  
    rf.id_house_listing,                                                                
    rf.id_region,                                                                       
    rf.id_user,                                                                         
    rf.country_code,
    YEAR(dt_booking) AS year,
    MONTH(dt_booking) AS month,
    DAY(dt_booking) AS day
  FROM
    datalake_booking.booking AS bk
  JOIN
    rent_flow_house_listing AS rf
      ON rf.id_booking = bk.id
  WHERE 
    bk.is_visit_completed = TRUE 
    AND bk.type = 'Visita'
    AND bk.visit_fup IN ('VaiNegociar',
          'NaoGostou',
          'VisitouSozinho',
          'Talvez')
    AND bk.dt_booking IS NOT NULL
    AND YEAR(dt_booking) = {year} 
    AND MONTH(dt_booking) = {month} 
    AND DAY(dt_booking) = {day}
  UNION ALL
  SELECT --offer_submitted 
    off.id_offer_context AS id_event,
    rf.id_booking,
    off.id_offer_context AS id_offer,
    rf.id_proposal,
    rf.id_contract,                                                                         
    3 AS id_event_type,                                                                                   
    off.id_client,                                                                      
    off.id_house,                                                                       
    rf.id_user_agent,                                                                   
    off.id_rent_flow,                                                                   
    off.ts_first_sent AS ts_event,                                                                 
    rf.id_house_listing,                                                                
    rf.id_region,                                                                       
    rf.id_user,                                                                         
    rf.country_code, 
    YEAR(ts_first_sent) AS year,
    MONTH(ts_first_sent) AS month,
    DAY(ts_first_sent) AS day
  FROM
    datalake_offer.offer AS off
  JOIN
    rent_flow_house_listing AS rf
      ON rf.id_offer = off.id_offer_context
  WHERE 
    ts_first_sent IS NOT NULL
    -- We're not implementing the incremental load for OS since this date information comes from Firestore.
    -- We noticed that the data is extracted in a certain day but the offer's first sent date is from days before,
    -- which lead to not being able to load it by incremental load.
  UNION ALL
  SELECT --offer_accepted
    off.id_offer_context AS id_event,
    rf.id_booking,
    off.id_offer_context AS id_offer,
    rf.id_proposal,
    rf.id_contract,                                                                           
    4 AS id_event_type,                                                                                 
    off.id_client,                                                                      
    off.id_house,                                                                       
    rf.id_user_agent,                                                                   
    off.id_rent_flow,                                                                   
    off.ts_analyzed AS ts_event,                                                                    
    rf.id_house_listing,                                                                
    rf.id_region,                                                                       
    rf.id_user,                                                                         
    rf.country_code,
    YEAR(ts_analyzed) AS year,
    MONTH(ts_analyzed) AS month,
    DAY(ts_analyzed) AS day
  FROM
    datalake_offer.offer AS off
  JOIN
    rent_flow_house_listing AS rf
      ON rf.id_offer = off.id_offer_context
  WHERE 
    off.status = 'Aprovada'
    AND ts_analyzed IS NOT NULL
    AND YEAR(ts_analyzed) = {year} 
    AND MONTH(ts_analyzed) = {month}
    AND DAY(ts_analyzed) = {day}
  UNION ALL
  SELECT --evaluation_started
    pp.id AS id_event,
    rf.id_booking,
    rf.id_offer,
    pp.id AS id_proposal,
    rf.id_contract,                                                                          
    5 AS id_event_type,                                                                                 
    off.id_client,                                                                      
    off.id_house,                                                                       
    rf.id_user_agent,                                                                   
    off.id_rent_flow,                                                                   
    pp.ts_credit_evaluation_first_init AS ts_event,                                                
    rf.id_house_listing,                                                                
    rf.id_region,                                                                       
    rf.id_user,                                                                         
    rf.country_code,
    YEAR(ts_credit_evaluation_first_init) AS year,
    MONTH(ts_credit_evaluation_first_init) AS month,
    DAY(ts_credit_evaluation_first_init) AS day
  FROM
    datalake_proposal.proposal AS pp
  JOIN
    datalake_offer.offer AS off
      ON off.id = pp.id_offer
  JOIN
    rent_flow_house_listing AS rf
      ON rf.id_proposal = pp.id
  WHERE 
    pp.ts_credit_evaluation_first_init IS NOT NULL
    AND YEAR(ts_credit_evaluation_first_init) = {year} 
    AND MONTH(ts_credit_evaluation_first_init) = {month}
    AND DAY(ts_credit_evaluation_first_init) = {day}
  UNION ALL
  SELECT --evaluation_positive
    pp.id AS id_event,
    rf.id_booking,
    rf.id_offer,
    pp.id AS id_proposal,
    rf.id_contract,                                                                              
    6 AS id_event_type,                                                                                 
    off.id_client,                                                                      
    off.id_house,                                                                       
    rf.id_user_agent,                                                                   
    off.id_rent_flow,                                                                   
    pp.ts_first_credit_evaluation_positive AS ts_event,                                              
    rf.id_house_listing,                                                                
    rf.id_region,                                                                       
    rf.id_user,                                                                         
    rf.country_code,     
    YEAR(ts_first_credit_evaluation_positive) AS year,
    MONTH(ts_first_credit_evaluation_positive) AS month,
    DAY(ts_first_credit_evaluation_positive) AS day
  FROM
    datalake_proposal.proposal AS pp
   JOIN
    datalake_offer.offer AS off
      ON off.id = pp.id_offer 
  JOIN
    rent_flow_house_listing AS rf
      ON rf.id_proposal = pp.id
  WHERE 
    pp.ts_first_credit_evaluation_positive IS NOT NULL
    AND YEAR(ts_first_credit_evaluation_positive) = {year} 
    AND MONTH(ts_first_credit_evaluation_positive) = {month}
    AND DAY(ts_first_credit_evaluation_positive) = {day}
  UNION ALL
  SELECT --document_sent
    pp.id AS id_event,
    rf.id_booking,
    rf.id_offer,
    pp.id AS id_proposal,
    rf.id_contract,                                                                           
    7 AS id_event_type,                                                                                 
    off.id_client,                                                                      
    off.id_house,                                                                       
    rf.id_user_agent,                                                                   
    off.id_rent_flow,                                                                   
    COALESCE(pp.ts_tenant_auto_first_doc_sent, pp.ts_tenant_first_doc_sent) AS ts_event,             
    rf.id_house_listing,                                                                
    rf.id_region,                                                                       
    rf.id_user,                                                                         
    rf.country_code,
    YEAR(COALESCE(pp.ts_tenant_auto_first_doc_sent, pp.ts_tenant_first_doc_sent)) AS year,
    MONTH(COALESCE(pp.ts_tenant_auto_first_doc_sent, pp.ts_tenant_first_doc_sent)) AS month,
    DAY(COALESCE(pp.ts_tenant_auto_first_doc_sent, pp.ts_tenant_first_doc_sent)) AS day
  FROM
    datalake_proposal.proposal AS pp
  JOIN
    datalake_offer.offer AS off
      ON off.id = pp.id_offer 
  JOIN
    rent_flow_house_listing AS rf
      ON rf.id_proposal = pp.id
  WHERE 
    pp.has_tenant_sent_documentation = TRUE
    AND (pp.ts_tenant_auto_first_doc_sent IS NOT NULL
      OR pp.ts_tenant_first_doc_sent IS NOT NULL)
    AND YEAR(COALESCE(pp.ts_tenant_auto_first_doc_sent, pp.ts_tenant_first_doc_sent)) = {year} 
    AND MONTH(COALESCE(pp.ts_tenant_auto_first_doc_sent, pp.ts_tenant_first_doc_sent)) = {month}
    AND DAY(COALESCE(pp.ts_tenant_auto_first_doc_sent, pp.ts_tenant_first_doc_sent)) = {day}
  UNION ALL
  SELECT --credit_approved 
    pp.id AS id_event,
    rf.id_booking,
    rf.id_offer,
    pp.id AS id_proposal,
    rf.id_contract,                                                                             
    8 AS id_event_type,                                                                                   
    off.id_client,                                                                      
    off.id_house,                                                                       
    rf.id_user_agent,                                                                   
    off.id_rent_flow,                                                                   
    pp.ts_credit_approved_last AS ts_event,                                                         
    rf.id_house_listing,                                                                
    rf.id_region,                                                                       
    rf.id_user,                                                                         
    rf.country_code,
    YEAR(ts_credit_approved_last) AS year,
    MONTH(ts_credit_approved_last) AS month,
    DAY(ts_credit_approved_last) AS day
  FROM
    datalake_proposal.proposal AS pp
  JOIN
    datalake_offer.offer AS off
      ON off.id = pp.id_offer 
  JOIN
    rent_flow_house_listing AS rf
      ON rf.id_proposal = pp.id
  WHERE 
    pp.ts_credit_approved_last IS NOT NULL
    AND YEAR(ts_credit_approved_last) = {year} 
    AND MONTH(ts_credit_approved_last) = {month}
    AND DAY(ts_credit_approved_last) = {day}
  UNION ALL
  SELECT --contract_signed
    ct.id AS id_event,
    rf.id_booking,
    rf.id_offer,
    rf.id_proposal,
    ct.id AS id_contract,                                                                           
    9 AS id_event_type,                                                                                  
    off.id_client,                                                                      
    ct.id_house,                                                                        
    rf.id_user_agent,                                                                   
    off.id_rent_flow,                                                                   
    ct.ts_signed AS ts_event,                                                                     
    rf.id_house_listing,                                                                
    rf.id_region,                                                                       
    rf.id_user,                                                                         
    rf.country_code,
    YEAR(ts_signed) AS year,
    MONTH(ts_signed) AS month,
    DAY(ts_signed) AS day
  FROM
    datalake_ebdb_contract.contract AS ct
  JOIN
    datalake_proposal.proposal AS pp
      ON ct.id_proposal = pp.id
  JOIN
    datalake_offer.offer AS off
      ON off.id = pp.id_offer 
  JOIN
    rent_flow_house_listing AS rf
      ON rf.id_contract = ct.id
  WHERE 
    ct.ts_signed IS NOT NULL
    AND YEAR(ts_signed) = {year} 
    AND MONTH(ts_signed) = {month}
    AND DAY(ts_signed) = {day}
)
SELECT
  id_event,
  id_booking,
  id_offer,
  id_proposal,
  id_contract,  
  id_event_type,
  id_client AS id_tenant_prospect,                                              
  id_house,                                                       
  id_user_agent AS id_agent,                                                         
  id_rent_flow,                                                   
  id_house_listing,                                                
  id_region,                                                       
  id_user AS id_owner,                                                          
  ts_event,                         
  country_code,
  year,
  month,
  day,
  NOW() AS ts_updated
FROM
  rent_demand_events     
