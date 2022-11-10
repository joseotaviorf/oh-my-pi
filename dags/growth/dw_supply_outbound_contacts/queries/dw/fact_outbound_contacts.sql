SELECT
    id_outbound_contact AS sk_outbound_contact,
    COALESCE(CAST(REPLACE(SUBSTRING(dt_prospect_created,1, 10),'-','') AS BIGINT), -1) AS sk_prospect_created_date,
    COALESCE(CAST(REPLACE(SUBSTRING(DATE(ts_webhook_sent),1, 10),'-','') AS BIGINT), -1) AS sk_contact_requested_date,
    COALESCE(CAST(REPLACE(SUBSTRING(DATE(ts_contacted),1, 10),'-','') AS BIGINT), -1) AS sk_contacted_date,
    id_wololo_prospect,
    id_prospect,
    id_user_dispatch,
    id_user_braze,
    id_canvas,
    id_step_canvas,
    COALESCE(ELEMENT_AT(contact_extra_info, "id_user_notification"), -1) AS id_jaiminho_user_notifications,
    COALESCE(ELEMENT_AT(contact_extra_info, "id_call_analyst"), -1) AS id_call_analyst,
    canvas_name,
    canvas_step_name,
    phone_number, 
    mkt_origin,
    contact_channel,
    ts_webhook_sent AS ts_contact_requested,
    ts_contacted, 
    NOW() AS ts_load
FROM
    datalake_supply_outbound_flows.supply_outbound_contacts