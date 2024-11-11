SELECT 
    bnae.id_user,
    bnae.id_app,
    bnae.city,
    bnae.platform,
    bnae.os_name,
    bnae.event_type,
    bnae.user_properties,
    bnae.event_properties,
    bnae.is_sale_agent,
    bnae.is_rent_agent,
    bnae.ts_event,
    bnae.year,
    bnae.month,
    bnae.day
FROM 
    datalake_amplitude_agents_app.agents_native_events AS bnae
WHERE
    MAKE_DATE(bnae.year, bnae.month, bnae.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND bnae.country = 'BR'
    AND bnae.has_login_status IS TRUE
    AND (
        bnae.is_sale_agent IS TRUE
        OR bnae.is_rent_agent IS TRUE
    )
UNION
SELECT 
    bse.id_user,
    bse.id_app,
    bse.city,
    bse.platform,
    bse.os_name,
    bse.event_type,
    bse.user_properties,
    bse.event_properties,
    bse.is_sale_agent,
    bse.is_rent_agent,
    bse.ts_event,
    bse.year,
    bse.month,
    bse.day
FROM 
    datalake_amplitude_agents_app.agents_search_events AS bse
WHERE
    MAKE_DATE(bse.year, bse.month, bse.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')