SELECT
    UUID() AS id,
    CAST(flsr.sk_reason_event AS STRING) business_id,
    flsr.sk_region AS location_id,
    dl.id_house AS property_id,
    dc.uuid_company AS company_uuid,
    dlc.business_context,
    dlr.reason,
    flsr.ts_reason_started AS ts_event,
    dd.year,
    dd.month,
    dd.day
FROM
    dw_rede.fact_lead_3p_status_reason AS flsr
JOIN
    dw_rede.dim_lead_3p_reason AS dlr
        ON flsr.sk_lead_3p_reason = dlr.sk_lead_3p_reason
JOIN
    dw_rede.dim_lead_3p_context AS dlc
        ON dlc.sk_lead_3p_context = flsr.sk_lead_3p_context
JOIN
    dw_public.dim_date AS dd
        ON flsr.sk_reason_started_date = dd.sk_date
JOIN
    dw_rede.dim_company AS dc
        ON dc.sk_company = flsr.sk_company
JOIN
    dw_rede.dim_lead_3p AS dl
        ON dl.sk_lead_3p = flsr.sk_lead_3p
WHERE
    MAKE_DATE(dd.year, dd.month, dd.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND dlc.business_context = 'SALE'
    AND dc.uuid_company IS NOT NULL