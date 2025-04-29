SELECT
    XXHASH64(ofe.id_agent, DATE(ofe.ts_event)) AS id_agent_performance,
    ofe.id_agent,
    COALESCE(COUNT(DISTINCT IF(ofe.id_event_type = 3, ofe.id_offer, NULL)), 0) AS total_offer_submitted,
    COALESCE(COUNT(DISTINCT IF(ofe.id_event_type = 4, ofe.id_offer, NULL)), 0) AS total_offer_approved,
    COALESCE(COUNT(DISTINCT IF(ofe.id_event_type = 7, ofe.id_offer, NULL)), 0) AS total_document_sent, 
    COALESCE(COUNT(DISTINCT IF(ofe.id_event_type = 8, ofe.id_offer, NULL)), 0) AS total_credit_approved, 
    COALESCE(COUNT(DISTINCT IF(ofe.id_event_type = 9, ofe.id_offer, NULL)), 0) AS total_contract_signed,
    COALESCE(COUNT(DISTINCT IF(ofe.id_event_type = 5, ofe.id_offer, NULL)), 0) AS total_proposal_evaluation_started, 
    DATE(ofe.ts_event) AS dt_reference,
    ofe.year,
    ofe.month,
    ofe.day
FROM
    datalake_visit_agent_performance.offer_flow_events AS ofe
WHERE
    ofe.has_direct_first_touchpoint IS FALSE
    AND ofe.id_agent IS NOT NULL
    AND DATE(ofe.ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
GROUP BY ALL