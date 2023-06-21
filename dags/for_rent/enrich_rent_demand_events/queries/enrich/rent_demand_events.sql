WITH rent_flow_house_listing AS (
  /**
  It was necessary to add some validations related to what's coming from this first CTE (based on the rent flows enriched table) because there
  we can find several bookings, offers, proposals and contracts that not necessarily are following the rules used for this table.
  If we don't apply these filters since the beginning, we can end up having on events like VB already having an id_contract that would not be
  the same contract found when the rent flow event is CS. 
  In order to not create any trouble and messy analisys, we decided to filter all ids based on the many possible filters since the beginning.
  **/ 
  SELECT
    rf.id_rent_flow,
    rf.id_house,
    COALESCE(
      CAST(
        rf.id_house ||
        LPAD(
        COALESCE(
          CAST(COALESCE(hl_contract.version, hl.version) AS VARCHAR(3)),'1'),3,'0') AS BIGINT), CAST(-1 AS BIGINT)
    ) AS id_house_listing,
    h.id_user,
    rf.id_client,
    rf.id_user_agent AS id_agent,
    h.id_region,
    CASE
      WHEN bk.type = 'Visita'
        AND (bk.ts_created IS NOT NULL OR (bk.dt_booking IS NOT NULL AND bk.is_visit_completed = TRUE AND bk.visit_fup IN ('VaiNegociar', 'NaoGostou', 'VisitouSozinho', 'Talvez'))) THEN rf.id_booking
      ELSE NULL
      /** Conditions to accept a booking:
        -    Booking type must be Visit, always
        -    Booking creation date not null (which indicates VB event)
        -    Booking date not null + visit completed + some visit fups (which indicates VC event)
        -    Other bookings not following these rules shouldn't be present at any time
      **/
    END AS id_booking,
    CASE
      WHEN rf.id_offer_context REGEXP '[0-1]{{2}}$' THEN NULL
      WHEN off.ts_first_sent IS NOT NULL OR (off.status = 'Aprovada' AND off.ts_analyzed IS NOT NULL) THEN rf.id_offer_context
      ELSE NULL
    END AS id_offer,
    /** Conditions to accept an offer:
      -    Offers that are not pre proposals ("offers" ending with 01)
      -    Offers that were sent (which indicates OS event)
      -    Offers that have status approved and have a timestamp of analysis (which indicates OA event)
    **/
    CASE
      WHEN pp.ts_credit_evaluation_first_init IS NOT NULL
        OR pp.ts_first_credit_evaluation_positive IS NOT NULL
        OR (pp.has_tenant_sent_documentation = TRUE OR (pp.ts_tenant_auto_first_doc_sent IS NOT NULL OR pp.ts_tenant_first_doc_sent IS NOT NULL))
        OR pp.ts_credit_approved_last IS NOT NULL THEN rf.id_proposal
      ELSE NULL
    END AS id_proposal,
    /** Conditions to accept a proposal:
      -    Proposals that have a credit evaluation first init date (which indicates ES event)
      -    Proposals that have a credit evaluation first positive date (which indicates EP event)
      -    Proposals that have tenant's documentation manual sent or auto doc sent dates (which indicates DS event)
      -    Proposals that have a credit approved last date (which indicates CA event)
    **/
    IF(con.ts_signed IS NOT NULL AND con.is_active_or_ended = TRUE, rf.id_contract, NULL) AS id_contract,
    /** Conditions to accept a contract:
      -    Contracts that have signed date and status like active or ended (which indicates CS event)
    **/
    COALESCE(h.country_code, 'Undefined') AS country_code
  FROM
    datalake_ebdb_rent_flow.rent_flow AS rf
  JOIN
    datalake_ebdb_listing.house_listing AS hl
      ON hl.id_house = rf.id_house
      AND COALESCE(rf.dt_rent_flow_created, '1900-01-01') BETWEEN COALESCE(hl.ts_listing_version_start, '1900-01-01')
        AND COALESCE(hl.ts_listing_version_end, NOW())
  LEFT JOIN
    datalake_ebdb_contract.contract AS con
      ON con.id_house = rf.id_house
      AND con.id = rf.id_contract
  LEFT JOIN
    datalake_ebdb_listing.house_listing AS hl_contract
      ON con.id_house = hl_contract.id_house 
      AND con.ts_created BETWEEN COALESCE(hl_contract.ts_listing_version_start, '2000-01-01 00:00:00') 
        AND COALESCE(hl_contract.ts_listing_version_end, CURRENT_DATE)
  LEFT JOIN
    datalake_ebdb_listing.house AS h
      ON hl.id_house = h.id
  LEFT JOIN
    datalake_ebdb_listing.listing_business_context AS lbc
      ON lbc.id_house = h.id
  LEFT JOIN
    datalake_booking.booking AS bk
      ON bk.id = rf.id_booking
  LEFT JOIN
    datalake_offer.offer AS off
      ON off.id_offer_context = rf.id_offer_context
  LEFT JOIN
    datalake_proposal.proposal AS pp
      ON pp.id = rf.id_proposal
  WHERE 
    (lbc.business_context = 'RENT'
    OR lbc.business_context IS NULL)
    /** Some properties exists on the House table but not on LBC. In order to keep the same rule/results
        that we have on the fact_listing_rent_flows, we decided to add another filter considering the business context as null
    **/
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
    bk.id_agent,
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
    bk.id_agent,                                                                        
    bk.id_rent_flow,                                                                    
    bk.ts_booking_utc AS ts_event,                                                                  
    rf.id_house_listing,                                                                
    rf.id_region,                                                                       
    rf.id_user,                                                                         
    rf.country_code,
    YEAR(ts_booking_utc) AS year,
    MONTH(ts_booking_utc) AS month,
    DAY(ts_booking_utc) AS day
  FROM
    datalake_booking.booking AS bk
  JOIN
    rent_flow_house_listing AS rf
      ON rf.id_booking = bk.id
  WHERE
    bk.type = 'Visita'
    AND bk.is_visit_completed = TRUE 
    AND bk.visit_fup IN ('VaiNegociar',
          'NaoGostou',
          'VisitouSozinho',
          'Talvez')
    AND bk.dt_booking IS NOT NULL
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
    rf.id_agent,                                                                   
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
    /** We're not implementing the incremental load for OS since this date information comes from Firestore.
      We noticed that the data is extracted in a certain day but the offer's first sent date is from days before,
      which lead to not being able to load it by incremental load
    **/
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
    rf.id_agent,                                                                   
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
    rf.id_agent,                                                                   
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
    rf.id_agent,                                                                   
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
  UNION ALL
  SELECT --document_sent
    pp.id AS id_event,
    rf.id_booking,
    rf.id_offer,
    pp.id AS id_proposal,
    rf.id_contract,                                                                           
    7 AS id_event_type,                                                                                 
    COALESCE(off.id_client, rf.id_client) AS id_client,
    COALESCE(off.id_house, rf.id_house) AS id_house,
    rf.id_agent,                                                                   
    COALESCE(off.id_rent_flow, rf.id_rent_flow) AS id_rent_flow,
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
    rent_flow_house_listing AS rf
      ON rf.id_proposal = pp.id
  LEFT JOIN -- We have properties from portability that don't have an offer but have a proposal and contract signed
    datalake_offer.offer AS off
      ON off.id = pp.id_offer 
  WHERE 
    pp.has_tenant_sent_documentation = TRUE
    OR (pp.ts_tenant_auto_first_doc_sent IS NOT NULL 
      OR pp.ts_tenant_first_doc_sent IS NOT NULL)
    /** Some proposals already had a documentation sent (which will be marked by the ts_tenant_first_doc_sent)
        but the boolean flag could turn into false. This behavior is mostly seen from 2022 backwards
    **/
  UNION ALL
  SELECT --credit_approved 
    pp.id AS id_event,
    rf.id_booking,
    rf.id_offer,
    pp.id AS id_proposal,
    rf.id_contract,                                                                             
    8 AS id_event_type,                                                                                   
    COALESCE(off.id_client, rf.id_client) AS id_client,                                                                   
    COALESCE(off.id_house, rf.id_house) AS id_house,                                                                  
    rf.id_agent,                                                                   
    COALESCE(off.id_rent_flow, rf.id_rent_flow) AS id_rent_flow,                                                               
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
    rent_flow_house_listing AS rf
      ON rf.id_proposal = pp.id
  LEFT JOIN   -- We have properties from portability that don't have an offer but have a proposal and contract signed
    datalake_offer.offer AS off
      ON off.id = pp.id_offer 
  WHERE 
    pp.ts_credit_approved_last IS NOT NULL
  UNION ALL
  SELECT --contract_signed
    ct.id AS id_event,
    rf.id_booking,
    rf.id_offer,
    rf.id_proposal,
    ct.id AS id_contract,                                                                           
    9 AS id_event_type,                                                                                  
    COALESCE(off.id_client, rf.id_client) AS id_client,                                                                  
    ct.id_house,                                                                        
    rf.id_agent,                                                                   
    COALESCE(off.id_rent_flow, rf.id_rent_flow) AS id_rent_flow,                                                               
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
    rent_flow_house_listing AS rf
      ON rf.id_contract = ct.id
  LEFT JOIN -- We may have several contracts without offer and proposal (portability). In order to don't lose track of them, we're applying a left join.
    datalake_proposal.proposal AS pp
      ON ct.id_proposal = pp.id
  LEFT JOIN
    datalake_offer.offer AS off
      ON off.id = pp.id_offer 
  WHERE 
    ct.ts_signed IS NOT NULL
    AND ct.is_active_or_ended = TRUE
)
SELECT DISTINCT
  /** As a rent flow may have N times the same booking/proposal/offer appearing related to different demand steps
  (e.g. a same booking related to different offers) and we want to every booking/proposal/offer follow the rules proposed
  on the first CTE, we need to apply a distinct in order to deduplicate it as events start to happen.
  **/ 
  id_event,
  id_booking,
  id_offer,
  id_proposal,
  id_contract,
  id_event_type,
  id_client AS id_tenant_prospect,
  id_house,
  id_agent,
  id_rent_flow,
  id_house_listing,
  id_region,
  id_user AS id_owner,
  ts_event,
  country_code,
  year AS event_year,
  month AS event_month,
  day AS event_day
FROM
  rent_demand_events