SELECT
    pklead AS id_vivareal_zap_lead,
    fkportal AS id_portal,
    codigo_cliente_portal AS id_portal_client,
    clientListingId AS client_listing_id,
    originListingId AS origin_listing_id,
    originLeadId AS origin_lead_id,
    leadOrigin AS lead_origin,
    name,
    email,
    ddd AS phone_area_code,
    phone,
    phoneNumber AS phone_number,
    message,
    status,
    timestamp AS ts_lead_received,
    paratime AS dt_paratime
FROM
    datalake_union_cdc_raw.leads_vivareal_zap
