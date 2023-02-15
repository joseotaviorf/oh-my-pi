SELECT
    MD5(STRING(csk.sk_company) || '-' || STRING(ce.id_journey) || '-' || STRING(dcet.sk_company_event_type)) AS sk_company_event,
    COALESCE(BIGINT(DATE_FORMAT(ce.ts_event, 'yyyyMMdd')), -1) AS sk_event_date,
    COALESCE(csk.sk_company, -1) AS sk_company,
    COALESCE(dcet.sk_company_event_type, -1) AS sk_company_event_type,
    csk.sk_company * 1000 + id_journey AS sk_company_journey,
    id_journey AS journey_number,
    ce.ts_event,
    NOW() AS ts_load
FROM
    datalake_rede_company.company_event AS ce
LEFT JOIN
    datalake_rede_company.company_sks AS csk
        ON ce.id_company = csk.id_hubspot
LEFT JOIN
    dw_rede.dim_company_event_type AS dcet
        ON COALESCE(ce.event, 'N/A') <=> dcet.event
        AND COALESCE(ce.event_type, 'N/A') <=> dcet.event_type
        AND COALESCE(ce.source_type, 'N/A') <=> dcet.source_type
        AND COALESCE(ce.hubspot_event_detail, 'N/A') <=> dcet.hubspot_event_detail
        AND COALESCE(ce.hubspot_event_origin, 'N/A') <=> dcet.hubspot_event_origin
        AND COALESCE(ce.hubspot_company_status, 'N/A') <=> dcet.hubspot_company_status
        AND COALESCE(ce.hubspot_deal_stage, 'N/A') <=> dcet.hubspot_deal_stage
        AND COALESCE(ce.hubspot_demand_onboarding_ticket_stage, 'N/A') <=> dcet.hubspot_demand_onboarding_ticket_stage
        AND COALESCE(ce.hubspot_supply_onboarding_ticket_stage, 'N/A') <=> dcet.hubspot_supply_onboarding_ticket_stage
