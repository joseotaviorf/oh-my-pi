WITH message_summary AS (
    SELECT DISTINCT 
        cht.id_ticket,
        cht.country_code,
        CAST(GET_JSON_OBJECT(evt.event_payload, '$.DateCreated') AS TIMESTAMP) AS ts_created_message,
        cht.ts_ticket_started,
        cht.ts_ticket_ended,
        REPLACE(GET_JSON_OBJECT(evt.event_payload, '$.Body'), ';', ',') AS message,
        GET_JSON_OBJECT(evt.event_payload, '$.From') AS message_from
    FROM 
        datalake_customer_support.chat AS cht
    INNER JOIN 
        datalake_quinto_messenger_clean.channel AS ch 
            ON cht.id_session = ch.id_source
    INNER JOIN 
        datalake_quinto_messenger_clean.channel_event AS evt 
            ON evt.id_channel_external = ch.id_external 
    LEFT JOIN
        datalake_zendesk_users.agents AS a
            ON cht.agent_email = a.email
    WHERE 
        cht.department IN (
        'CX Visitas [FRONT] [PRE]',
        'CX Propostas [FRONT] [PRE]',
        'CX Mudança [FRONT] [POS]',
        'CX Parceiros [FRONT] [PRE]',
        'CX Parceiros da Portaria [FRONT] [PRE]',
        'Consultores imobiliários 5A',
        'CX Ação Plaquinhas [FRONT] [PRE]',
        'CX Pagamentos [FRONT] [POS]',
        'CX Reparos [FRONT] [POS]',
        'CX Rescisão [FRONT] [POS]',
        'CX Compra e Venda [FRONT] [PRE] [POS]',
        'CX Parceiros Compra e Venda [FRONT]',
        'CX Durante a locação e reparos [POS] [FRONT]',
        'CX Entrada no imóvel [ONB] [POS] [FRONT]',
        'CX Mudança [FRONT] [POS]',
        'CX Pagamentos [FRONT] [POS]',
        'CX Pagamentos N1 [PAY] [POS] [FRONT]',
        'CX Parceiros [FRONT] [PRE]',
        'CX Parceiros Compra e Venda [FRONT]',
        'CX Parceiros da Portaria [FRONT] [PRE]',
        'CX Propostas [FRONT] [PRE]',
        'CX PROPOSTAS CALL/CHAT [PRO][PRE][FRONT]',
        'CX Reparos [FRONT] [POS]',
        'CX Rescisão [FRONT] [POS]',
        'CX Rescisão e Vistoria [OFF] [POS] [FRONT]',
        'CX Visitas [FRONT] [PRE]',
        'CX Visitas N1 & N2 [VIS] [PRE] [FRONT] [OUT]',
        'PARTNERS/CIQ [FRONT] [PRE]',
        'ProOwners [FRONT] [PRE] [POS]'
        )
        AND a.organization IN ('webhelp', 'webhelpbr')
        AND DATE(cht.ts_segment_closed) = CURRENT_DATE() - 1
)
SELECT 
    id_ticket,
    country_code,
    ts_ticket_started,
    ts_ticket_ended,
    ts_created_message,
    message,
    CASE 
        WHEN message_from LIKE '%whatsapp%' THEN 'client' 
        ELSE message_from 
    END AS message_from,
    YEAR(CURRENT_DATE - 1) AS year,
    MONTH(CURRENT_DATE - 1) AS month,
    DAY(CURRENT_DATE - 1) AS day,
    NOW() AS ts_load
FROM 
    message_summary
