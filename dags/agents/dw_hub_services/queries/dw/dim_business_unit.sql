SELECT 
    bu.id AS sk_business_unit,
    bu.hub_name,
    bu.business_context,
    bu.sdr_type,
    bu.negotiation_type,
    bu.ts_created,
    bu.ts_updated,
    NOW() AS ts_load
FROM
    datalake_hub_services_clean.business_unit AS bu 