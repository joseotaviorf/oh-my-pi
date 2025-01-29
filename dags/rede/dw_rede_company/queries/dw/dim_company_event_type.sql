WITH combinations AS (
    SELECT DISTINCT
        COALESCE(business_context, 'N/A') AS business_context,
        COALESCE(event, 'N/A') AS event,
        COALESCE(event_type, 'N/A') AS event_type,
        COALESCE(source_type, 'N/A') AS source_type,
        COALESCE(hubspot_event_detail, 'N/A') AS hubspot_event_detail,
        COALESCE(hubspot_event_origin, 'N/A') AS hubspot_event_origin,
        COALESCE(hubspot_company_status, 'N/A') AS hubspot_company_status,
        COALESCE(hubspot_deal_stage, 'N/A') AS hubspot_deal_stage,
        COALESCE(hubspot_demand_onboarding_ticket_stage, 'N/A') AS hubspot_demand_onboarding_ticket_stage,
        COALESCE(hubspot_supply_onboarding_ticket_stage, 'N/A') AS hubspot_supply_onboarding_ticket_stage
    FROM
        datalake_rede_company_event.company_event
),
last_sk_values AS (
    SELECT
        COALESCE(MAX(sk_company_event_type), 0) AS sk_company_event_type
    FROM
        dw_rede.dim_company_event_type
)
SELECT
    COALESCE(
        dcet.sk_company_event_type,
        last_sk_values.sk_company_event_type + MONOTONICALLY_INCREASING_ID() + 1
    ) AS sk_company_event_type,
    business_context,
    event,
    event_type,
    source_type,
    hubspot_event_detail,
    hubspot_event_origin,
    hubspot_company_status,
    hubspot_deal_stage,
    hubspot_demand_onboarding_ticket_stage,
    hubspot_supply_onboarding_ticket_stage,
    COALESCE(dcet.ts_load, NOW()) AS ts_load
FROM
    combinations AS c,
    last_sk_values
FULL OUTER JOIN
    dw_rede.dim_company_event_type AS dcet
        USING (
            business_context,
            event,
            event_type,
            source_type,
            hubspot_event_detail,
            hubspot_event_origin,
            hubspot_company_status,
            hubspot_deal_stage,
            hubspot_demand_onboarding_ticket_stage,
            hubspot_supply_onboarding_ticket_stage
        )
WHERE
    dcet.sk_company_event_type IS DISTINCT FROM -1
