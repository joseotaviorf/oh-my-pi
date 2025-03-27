WITH all_leads AS (
    SELECT
        ags.id_agent,
        ags.id_lead,
        DATE(ags.ts_created) AS dt_reference
    FROM
        datalake_visit_agent_performance.agent_schedules AS ags
    WHERE
        ags.has_direct_first_touchpoint IS FALSE
        AND DATE(ags.ts_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    UNION
    SELECT
        ofe.id_agent,
        ofe.id_lead,
        DATE(ofe.ts_event) AS dt_reference
    FROM
        datalake_visit_agent_performance.offer_flow_events AS ofe
    WHERE
        ofe.has_direct_first_touchpoint IS FALSE
        AND DATE(ofe.ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT /*+ RANGE_JOIN(ac, 1500) */ 
    XXHASH64(ac.id_agent, ad.date) AS id_agent_performance,
    ac.id_agent,
    -- SIZE(ARRAY_DISTINCT(FILTER(ARRAY(ags.id_lead, ofe.id_lead), x -> x IS NOT NULL))) AS total_leads,
    COALESCE(COUNT(DISTINCT al.id_lead), 0) AS total_leads,
    COALESCE(COUNT(DISTINCT ags.id_lead) FILTER (WHERE ags.has_three_or_more_confirmed_visits_same_agent IS TRUE), 0) AS total_leads_with_three_or_more_confirmed_visits,
    COALESCE(COUNT(DISTINCT ags.id_lead), 0) AS total_lead_to_visit_booking,
    COALESCE(COUNT(DISTINCT ags.id_lead) FILTER (WHERE ags.is_visit_booking_by_agent IS TRUE), 0) AS total_lead_to_visit_booking_by_agent,
    COALESCE(COUNT(DISTINCT ags.id_lead) FILTER (WHERE ags.is_visit_completed IS TRUE AND ags.is_visit_completed IS TRUE), 0) AS total_lead_to_visit_completed,
    COALESCE(COUNT(DISTINCT IF(ofe.id_event_type = 3, ofe.id_lead, NULL)), 0) AS total_lead_to_offer_submitted,
    COALESCE(COUNT(DISTINCT IF(ofe.id_event_type = 4, ofe.id_lead, NULL)), 0) AS total_lead_to_offer_approved,
    COALESCE(COUNT(DISTINCT IF(ofe.id_event_type = 7, ofe.id_lead, NULL)), 0) AS total_lead_to_document_sent, 
    COALESCE(COUNT(DISTINCT IF(ofe.id_event_type = 8, ofe.id_lead, NULL)), 0) AS total_lead_to_credit_approved, 
    COALESCE(COUNT(DISTINCT IF(ofe.id_event_type = 9, ofe.id_lead, NULL)), 0) AS total_lead_to_contract_signed,
    COALESCE(COUNT(DISTINCT IF(ofe.id_event_type = 5, ofe.id_lead, NULL)), 0) AS total_lead_to_proposal_evaluation_started, 
    COALESCE(
        COUNT(
            DISTINCT CASE
                WHEN ags.id_lead = ofe.id_lead
                AND DATEDIFF(
                    IF(ofe.id_event_type = 9, ofe.ts_event, NULL),
                    ags.ts_created
                ) <= 7
                THEN ofe.id_lead
            END
        )
    , 0) AS total_leads_to_contract_signed_cohort_7_days,
    ad.date AS dt_reference,
    ad.year,
    ad.month,
    ad.day
FROM
    datalake_agent_accreditation.business_context_activity AS ac
JOIN  
    datalake_quintoandar.aux_date AS ad
        ON ad.date BETWEEN ac.dt_started AND ac.dt_ended
LEFT JOIN
    datalake_visit_agent_performance.agent_schedules AS ags
        ON ags.id_agent = ac.id_agent
        AND ags.year = ad.year
        AND ags.month = ad.month
        AND ags.day = ad.day
        AND ags.has_direct_first_touchpoint IS FALSE
LEFT JOIN
    datalake_visit_agent_performance.offer_flow_events AS ofe
        ON ofe.id_agent = ac.id_agent
        AND ofe.year = ad.year
        AND ofe.month = ad.month
        AND ofe.day = ad.day
        AND ofe.has_direct_first_touchpoint IS FALSE
LEFT JOIN
    all_leads AS al
        ON al.id_agent = ac.id_agent
        AND al.dt_reference = ad.date
WHERE
    COALESCE(ags.id_agent, ofe.id_agent) IS NOT NULL
    AND ad.date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
GROUP BY ALL