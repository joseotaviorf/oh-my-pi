WITH base_dates AS (
    SELECT
        dc.sk_company_lead * 10000 + IF(ce.business_context = 'SALE', 0, 1) * 1000 + id_journey AS sk_company_journey,
        dc.sk_company_lead,
        dc.sk_company,
        ce.id_company,
        id_journey AS journey_number,
        ce.business_context,
        dc.country_code,
        MIN(ts_event) AS ts_lead,
        MIN(
            CASE
                WHEN event IN (
                    'Prospect', 'Growth Mkt Nutrition', 'Negotiation Meeting Pending', 'Negotiation Meeting Scheduled',
                    'Negotiation Meeting Completed', 'Negotiation In Progress', 'Deal Won', 'Awaiting Documents',
                    'Documents Received', 'Term Sent', 'Pre Qualified', 'Qualified', 'Opportunity', 'Membership Started'
                ) THEN ts_event
            END
        ) AS ts_prospect,
        MIN(
            CASE
                WHEN event IN (
                    'Negotiation Meeting Pending', 'Negotiation Meeting Scheduled',
                    'Negotiation Meeting Completed', 'Negotiation In Progress', 'Deal Won', 'Awaiting Documents',
                    'Documents Received', 'Term Sent', 'Pre Qualified', 'Qualified', 'Opportunity', 'Membership Started'
                ) THEN ts_event
            END
        ) AS ts_pre_qualified,
        MIN(
            CASE
                WHEN event IN (
                    'Negotiation Meeting Scheduled',
                    'Negotiation Meeting Completed', 'Negotiation In Progress', 'Deal Won', 'Awaiting Documents',
                    'Documents Received', 'Term Sent', 'Qualified', 'Opportunity', 'Membership Started'
                ) THEN ts_event
            END
        ) AS ts_qualified,
        MIN(
            CASE
                WHEN event IN (
                    'Deal Won', 'Awaiting Documents', 'Documents Received',
                    'Term Sent', 'Opportunity', 'Membership Started'
                ) THEN ts_event
            END
        ) AS ts_opportunity,
        MIN(
            CASE
                WHEN event IN (
                    'Deal Won', 'Awaiting Documents', 'Documents Received',
                    'Term Sent', 'Membership Started'
                ) THEN ts_event
            END
        ) AS ts_deal_won,
        MIN(
            CASE
                WHEN event = 'Deal Lost' THEN ts_event
            END
        ) AS ts_deal_lost,
        MIN(
            CASE
                WHEN event IN (
                    'Awaiting Documents', 'Term Sent', 'Membership Started'
                ) THEN ts_event
            END
        ) AS ts_awaiting_documents,
        MIN(
            CASE
                WHEN event IN (
                    'Term Sent', 'Membership Started'
                ) THEN ts_event
            END
        ) AS ts_term_sent,
        MIN(
            CASE
                WHEN event = 'Membership Started' THEN ts_event
            END
        ) AS ts_membership_started,
        MIN(
            CASE
                WHEN event = 'Demand Onboarding Scheduled' THEN ts_event
            END
        ) AS ts_demand_onboarding_scheduled,
        MIN(
            CASE
                WHEN event = 'Supply Onboarding Scheduled' THEN ts_event
            END
        ) AS ts_supply_onboarding_scheduled,
        MIN(
            CASE
                WHEN event = 'First Lead 3P' THEN ts_event
            END
        ) AS ts_first_lead_3p,
        MIN(
            CASE
                WHEN event = 'First Listing' THEN ts_event
            END
        ) AS ts_first_listing,
        MIN(
            CASE
                WHEN event = 'First Demand Visit Booked' THEN ts_event
            END
        ) AS ts_first_demand_visit_booked,
        MIN(
            CASE
                WHEN event = 'Churn Risk' THEN ts_event
            END
        ) AS ts_churn_risk,
        MIN(
            CASE
                WHEN event = 'Contract Termination Analysis' THEN ts_event
            END
        ) AS ts_contract_termination_analysis,
        MIN(
            CASE
                WHEN event = 'Membership Ended' THEN ts_event
            END
        ) AS ts_membership_ended,
        MIN(
            CASE
                WHEN event = 'Contract Transition Started' THEN ts_event
            END
        ) AS ts_contract_transition_started,
        MIN(
            CASE
                WHEN event = 'Contract Transition Completed' THEN ts_event
            END
        ) AS ts_contract_transition_completed,
        MIN(
            CASE
                WHEN event = 'Churn' THEN ts_event
            END
        ) AS ts_churn,
        MAX(
            CASE
                WHEN event IN ('Membership Ended', 'Deal Lost') THEN ts_event
            END
        ) AS ts_journey_ended
    FROM
        datalake_rede_company_event.company_event AS ce
    JOIN
        dw_rede.dim_company_lead AS dc
            ON ce.id_company = dc.id_hubspot
    GROUP BY 1,2,3,4,5,6,7
),
leads_3p AS (
    SELECT
        id_company_hubspot,
        id_lead_3p,
        business_context,
        MIN(ts_status_started) AS ts_lead
    FROM
        datalake_rede_supply.lead_3p_status_changes
    GROUP BY 1,2,3
),
lead_3p_count_per_journey AS (
    SELECT
        bd.sk_company_journey,
        COUNT(*) AS leads_sent_through_supply_processor
    FROM
        base_dates AS bd
    JOIN
        leads_3p AS l
            ON bd.id_company = l.id_company_hubspot
            AND bd.business_context = l.business_context
            AND l.ts_lead BETWEEN bd.ts_lead AND COALESCE(bd.ts_journey_ended, NOW())
    GROUP BY 1
),
first_listings_count_per_journey AS (
    SELECT
        bd.sk_company_journey,
        COUNT(*) AS first_listings
    FROM
        base_dates AS bd
    JOIN
        datalake_ebdb_listing.house AS h
            ON bd.id_company = h.id_company_hubspot
    JOIN
        datalake_ebdb_clean.listing_business_context AS lbc
            ON h.id = lbc.id_house
            AND bd.business_context = lbc.business_context
            AND lbc.ts_first_publication BETWEEN bd.ts_lead AND COALESCE(bd.ts_journey_ended, NOW())
    GROUP BY 1
),
demand_bookings_per_journey AS (
    SELECT
        bd.sk_company_journey,
        COUNT(*) AS demand_bookings
    FROM
        base_dates AS bd
    JOIN
        datalake_booking.booking AS b
            ON bd.id_company = b.id_company_demand
            AND bd.business_context = b.visit_intent
            AND b.ts_created BETWEEN bd.ts_lead AND COALESCE(bd.ts_journey_ended, NOW())
    GROUP BY 1
)
SELECT
    bd.sk_company_journey,
    bd.sk_company_lead,
    bd.sk_company,
    bd.country_code,
    COALESCE(BIGINT(DATE_FORMAT(bd.ts_lead, 'yyyyMMdd')), -1) AS sk_lead_date,
    COALESCE(BIGINT(DATE_FORMAT(bd.ts_prospect, 'yyyyMMdd')), -1) AS sk_prospect_date,
    COALESCE(BIGINT(DATE_FORMAT(bd.ts_pre_qualified, 'yyyyMMdd')), -1) AS sk_pre_qualified_date,
    COALESCE(BIGINT(DATE_FORMAT(bd.ts_qualified, 'yyyyMMdd')), -1) AS sk_qualified_date,
    COALESCE(BIGINT(DATE_FORMAT(bd.ts_opportunity, 'yyyyMMdd')), -1) AS sk_opportunity_date,
    COALESCE(BIGINT(DATE_FORMAT(bd.ts_deal_won, 'yyyyMMdd')), -1) AS sk_deal_won_date,
    COALESCE(BIGINT(DATE_FORMAT(bd.ts_deal_lost, 'yyyyMMdd')), -1) AS sk_deal_lost_date,
    COALESCE(BIGINT(DATE_FORMAT(bd.ts_awaiting_documents, 'yyyyMMdd')), -1) AS sk_awaiting_documents_date,
    COALESCE(BIGINT(DATE_FORMAT(bd.ts_term_sent, 'yyyyMMdd')), -1) AS sk_term_sent_date,
    COALESCE(BIGINT(DATE_FORMAT(bd.ts_membership_started, 'yyyyMMdd')), -1) AS sk_membership_started_date,
    COALESCE(BIGINT(DATE_FORMAT(bd.ts_demand_onboarding_scheduled, 'yyyyMMdd')), -1) AS sk_demand_onboarding_scheduled_date,
    COALESCE(BIGINT(DATE_FORMAT(bd.ts_supply_onboarding_scheduled, 'yyyyMMdd')), -1) AS sk_supply_onboarding_scheduled_date,
    COALESCE(BIGINT(DATE_FORMAT(bd.ts_first_lead_3p, 'yyyyMMdd')), -1) AS sk_first_lead_3p_date,
    COALESCE(BIGINT(DATE_FORMAT(bd.ts_first_listing, 'yyyyMMdd')), -1) AS sk_first_listing_date,
    COALESCE(BIGINT(DATE_FORMAT(bd.ts_first_demand_visit_booked, 'yyyyMMdd')), -1) AS sk_first_demand_visit_booked_date,
    COALESCE(BIGINT(DATE_FORMAT(bd.ts_churn_risk, 'yyyyMMdd')), -1) AS sk_churn_risk_date,
    COALESCE(BIGINT(DATE_FORMAT(bd.ts_contract_termination_analysis, 'yyyyMMdd')), -1) AS sk_contract_termination_analysis_date,
    COALESCE(BIGINT(DATE_FORMAT(bd.ts_membership_ended, 'yyyyMMdd')), -1) AS sk_membership_ended_date,
    COALESCE(BIGINT(DATE_FORMAT(bd.ts_contract_transition_started, 'yyyyMMdd')), -1) AS sk_contract_transition_started_date,
    COALESCE(BIGINT(DATE_FORMAT(bd.ts_contract_transition_completed, 'yyyyMMdd')), -1) AS sk_contract_transition_completed_date,
    COALESCE(BIGINT(DATE_FORMAT(bd.ts_churn, 'yyyyMMdd')), -1) AS sk_churn_date,
    COALESCE(BIGINT(DATE_FORMAT(bd.ts_journey_ended, 'yyyyMMdd')), -1) AS sk_journey_ended_date,
    bd.journey_number,
    COALESCE(lpj.leads_sent_through_supply_processor, 0) AS leads_sent_through_supply_processor,
    COALESCE(flpj.first_listings, 0) AS first_listings,
    COALESCE(dbpj.demand_bookings, 0) AS demand_bookings,
    ROUND((UNIX_TIMESTAMP(bd.ts_prospect) - UNIX_TIMESTAMP(bd.ts_lead))/(24 * 60 * 60.0),5) AS days_lead_to_prospect,
    ROUND((UNIX_TIMESTAMP(bd.ts_pre_qualified) - UNIX_TIMESTAMP(bd.ts_lead))/(24 * 60 * 60.0),5) AS days_lead_to_pre_qualified,
    ROUND((UNIX_TIMESTAMP(bd.ts_qualified) - UNIX_TIMESTAMP(bd.ts_lead))/(24 * 60 * 60.0),5) AS days_lead_to_qualified,
    ROUND((UNIX_TIMESTAMP(bd.ts_opportunity) - UNIX_TIMESTAMP(bd.ts_lead))/(24 * 60 * 60.0),5) AS days_lead_to_opportunity,
    ROUND((UNIX_TIMESTAMP(bd.ts_deal_won) - UNIX_TIMESTAMP(bd.ts_lead))/(24 * 60 * 60.0),5) AS days_lead_to_deal_won,
    ROUND((UNIX_TIMESTAMP(bd.ts_deal_lost) - UNIX_TIMESTAMP(bd.ts_lead))/(24 * 60 * 60.0),5) AS days_lead_to_deal_lost,
    ROUND((UNIX_TIMESTAMP(bd.ts_awaiting_documents) - UNIX_TIMESTAMP(bd.ts_lead))/(24 * 60 * 60.0),5) AS days_lead_to_awaiting_documents,
    ROUND((UNIX_TIMESTAMP(bd.ts_term_sent) - UNIX_TIMESTAMP(bd.ts_lead))/(24 * 60 * 60.0),5) AS days_lead_to_term_sent,
    ROUND((UNIX_TIMESTAMP(bd.ts_membership_started) - UNIX_TIMESTAMP(bd.ts_lead))/(24 * 60 * 60.0),5) AS days_lead_to_membership_started,
    ROUND((UNIX_TIMESTAMP(bd.ts_demand_onboarding_scheduled) - UNIX_TIMESTAMP(bd.ts_lead))/(24 * 60 * 60.0),5) AS days_lead_to_demand_onboarding_scheduled,
    ROUND((UNIX_TIMESTAMP(bd.ts_supply_onboarding_scheduled) - UNIX_TIMESTAMP(bd.ts_lead))/(24 * 60 * 60.0),5) AS days_lead_to_supply_onboarding_scheduled,
    ROUND((UNIX_TIMESTAMP(bd.ts_first_lead_3p) - UNIX_TIMESTAMP(bd.ts_lead))/(24 * 60 * 60.0),5) AS days_lead_to_first_lead_3p,
    ROUND((UNIX_TIMESTAMP(bd.ts_first_listing) - UNIX_TIMESTAMP(bd.ts_lead))/(24 * 60 * 60.0),5) AS days_lead_to_first_listing,
    ROUND((UNIX_TIMESTAMP(bd.ts_first_demand_visit_booked) - UNIX_TIMESTAMP(bd.ts_lead))/(24 * 60 * 60.0),5) AS days_lead_to_first_demand_visit_booked,
    ROUND((UNIX_TIMESTAMP(bd.ts_churn_risk) - UNIX_TIMESTAMP(bd.ts_lead))/(24 * 60 * 60.0),5) AS days_lead_to_churn_risk,
    ROUND((UNIX_TIMESTAMP(bd.ts_contract_termination_analysis) - UNIX_TIMESTAMP(bd.ts_lead))/(24 * 60 * 60.0),5) AS days_lead_to_contract_termination_analysis,
    ROUND((UNIX_TIMESTAMP(bd.ts_membership_ended) - UNIX_TIMESTAMP(bd.ts_lead))/(24 * 60 * 60.0),5) AS days_lead_to_membership_ended,
    ROUND((UNIX_TIMESTAMP(bd.ts_contract_transition_started) - UNIX_TIMESTAMP(bd.ts_lead))/(24 * 60 * 60.0),5) AS days_lead_to_contract_transition_started,
    ROUND((UNIX_TIMESTAMP(bd.ts_contract_transition_completed) - UNIX_TIMESTAMP(bd.ts_lead))/(24 * 60 * 60.0),5) AS days_lead_to_contract_transition_completed,
    ROUND((UNIX_TIMESTAMP(bd.ts_churn) - UNIX_TIMESTAMP(bd.ts_lead))/(24 * 60 * 60.0),5) AS days_lead_to_churn,
    ROUND((UNIX_TIMESTAMP(bd.ts_journey_ended) - UNIX_TIMESTAMP(bd.ts_lead))/(24 * 60 * 60.0),5) AS days_lead_to_journey_ended,
    bd.ts_lead,
    bd.ts_prospect,
    bd.ts_pre_qualified,
    bd.ts_qualified,
    bd.ts_opportunity,
    bd.ts_deal_won,
    bd.ts_deal_lost,
    bd.ts_awaiting_documents,
    bd.ts_term_sent,
    bd.ts_membership_started,
    bd.ts_demand_onboarding_scheduled,
    bd.ts_supply_onboarding_scheduled,
    bd.ts_first_lead_3p,
    bd.ts_first_listing,
    bd.ts_first_demand_visit_booked,
    bd.ts_churn_risk,
    bd.ts_contract_termination_analysis,
    bd.ts_membership_ended,
    bd.ts_contract_transition_started,
    bd.ts_contract_transition_completed,
    bd.ts_churn,
    bd.ts_journey_ended,
    NOW() AS ts_load,
    bd.business_context
FROM
    base_dates AS bd
LEFT JOIN
    lead_3p_count_per_journey AS lpj
        ON lpj.sk_company_journey = bd.sk_company_journey
LEFT JOIN
    first_listings_count_per_journey AS flpj
        ON flpj.sk_company_journey = bd.sk_company_journey
LEFT JOIN
    demand_bookings_per_journey AS dbpj
        ON dbpj.sk_company_journey = bd.sk_company_journey
