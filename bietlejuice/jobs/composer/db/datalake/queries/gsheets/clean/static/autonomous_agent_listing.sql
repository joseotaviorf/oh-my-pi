SELECT
    id_user_lead,
    CAST(id_partner AS BIGINT) AS id_partner,
    user_email,
    user_name,
    phone,
    lead_origin,
    utm_source,
    utm_campaing,
    city_group,
    TO_DATE(dt_visitor, 'MM/dd/yyyy') AS dt_visitor,
    TO_DATE(dt_lead, 'MM/dd/yyyy') AS dt_lead,
    TO_DATE(dt_qualified_lead, 'MM/dd/yyyy') AS dt_qualified_lead,
    TO_DATE(dt_qualified_registred, 'MM/dd/yyyy') AS dt_qualified_registred,
    TO_DATE(dt_term_sent, 'MM/dd/yyyy') AS dt_term_sent,
    TO_DATE(dt_term_signed, 'MM/dd/yyyy') AS dt_term_signed,
    TO_DATE(dt_logged_in, 'MM/dd/yyyy') AS dt_logged_in
FROM
    datalake_gsheets_raw.autonomous_agent_listing