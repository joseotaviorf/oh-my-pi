SELECT
    MD5(
        STRING(dc.sk_company_lead) || '-' ||
        STRING(ce.id_journey) || '-' ||
        STRING(dcet.sk_company_event_type) || '-' ||
        STRING(ce.business_context)
    ) AS sk_company_event,
    COALESCE(BIGINT(DATE_FORMAT(ce.ts_event, 'yyyyMMdd')), -1) AS sk_event_date,
    COALESCE(dc.sk_company_lead, -1) AS sk_company_lead,
    COALESCE(dc.sk_company, -1) AS sk_company,
    COALESCE(dcet.sk_company_event_type, -1) AS sk_company_event_type,
    dc.sk_company_lead * 10000 + IF(ce.business_context = 'SALE', 0, 1) * 1000 + id_journey AS sk_company_journey,
    id_journey AS journey_number,
    ce.ts_event,
    NOW() AS ts_load,
    ce.business_context,
    dc.country_code
FROM
    datalake_rede_company_event.company_event AS ce
JOIN
    dw_rede.dim_company_lead AS dc
        ON ce.id_company = dc.id_hubspot
LEFT JOIN
    dw_rede.dim_company_event_type AS dcet
        ON COALESCE(ce.business_context, 'N/A') <=> dcet.business_context
        AND COALESCE(ce.event, 'N/A') <=> dcet.event
        AND COALESCE(ce.event_type, 'N/A') <=> dcet.event_type
        AND COALESCE(ce.source_type, 'N/A') <=> dcet.source_type
        AND COALESCE(ce.hubspot_event_detail, 'N/A') <=> dcet.hubspot_event_detail
        AND COALESCE(ce.hubspot_event_origin, 'N/A') <=> dcet.hubspot_event_origin
        AND COALESCE(ce.hubspot_company_status, 'N/A') <=> dcet.hubspot_company_status
        AND COALESCE(ce.hubspot_deal_stage, 'N/A') <=> dcet.hubspot_deal_stage
        AND COALESCE(ce.hubspot_demand_onboarding_ticket_stage, 'N/A') <=> dcet.hubspot_demand_onboarding_ticket_stage
        AND COALESCE(ce.hubspot_supply_onboarding_ticket_stage, 'N/A') <=> dcet.hubspot_supply_onboarding_ticket_stage
