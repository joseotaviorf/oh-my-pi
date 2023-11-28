WITH pp_tickets_test  as (
    SELECT DISTINCT
        tf.id_ticket,
        tf.client_type,
        sr.id_repair_request AS id_request
    FROM 
        datalake_zendesk_ticket_funnels.ticket_funnel AS tf
    INNER JOIN 
        datalake_repairs_clean.service_request AS sr 
            ON sr.id_third_party_crm_ticket_external = tf.id_ticket
    WHERE 
        tf.tags LIKE '%teste_ps_pp_grupo_b_intermediacao_autosservico%'
),
relisting_db AS (
    SELECT
        rf.id_contract,
        IF(hl.version >= 0, hl.id_house_listing, NULL) AS listing
    FROM
        datalake_ebdb_rent_flow.rent_flow AS rf
    LEFT JOIN
        datalake_ebdb_listing.house_listing AS hl
            ON rf.id_house = hl.id_house
    LEFT JOIN
        datalake_ebdb_listing.house AS h
            ON rf.id_house = h.id
    WHERE 
        DATE_TRUNC('month',hl.ts_listing_version_start) >= ADD_MONTHS(DATE_TRUNC('month',CURRENT_DATE),-47)
        AND DATE_TRUNC('month',hl.ts_listing_version_start) <= DATE_ADD(CURRENT_DATE, -1)
        AND (hl.listing_category = 'Re-Listing')
        AND ((h.country_code <> 'MX') OR (h.country_code IS NULL))
),
relisting_distinct AS (
    SELECT
        id_contract,
        COUNT(DISTINCT listing) AS relisting
    FROM
        relisting_db
    WHERE
        id_contract IS NOT NULL
    GROUP BY 1
),
repairs_interaction AS (
    SELECT
        rr.id AS id_request,
        IF(rc.ts_started IS NOT NULL, TRUE, FALSE) AS has_chat_negociation,
        CASE 
            WHEN MIN(rr.ts_updated) <= rc.ts_started THEN MIN(rr.ts_updated) - INTERVAL 3 HOUR
            WHEN MIN(rr.ts_updated) > rc.ts_started THEN rc.ts_started - INTERVAL 3 HOUR
            ELSE COALESCE(MIN(rr.ts_updated) - INTERVAL 3 HOUR, rc.ts_started - INTERVAL 3 HOUR) 
        END AS ts_first_interaction,
        MIN(DATE(rr.ts_updated)) AS definition_date
    FROM
        datalake_repairs_clean.repair_request AS rr
    LEFT JOIN
        datalake_repairs_clean.repair_request_chat AS rc
            ON rr.id = rc.id_repair_request
    WHERE
        (STRING(GET_JSON_OBJECT(rr.owner_approval, '$.approved')) IS NOT NULL)
        AND CAST(rr.ts_created AS DATE) >= DATE('2023-01-01')
        AND rr.id_third_party_crm_ticket_external IS NOT NULL
    GROUP BY 
        rr.id, rc.ts_started 
)
SELECT 
    tf.id_ticket,
    rr.id AS id_request,
    tfm.id_contract,
    tf.group_name,
    tf.client_type,
    tf.status,
    tf.custom_fields,
    tf.tags,
    tf.ticket_via,
    tf.channel,
    tf.agent_email,
    tf.agent_organization,
    rr.service_provider,
    COALESCE(chat.contact_theme_tag, call.contact_theme_tag, email.contact_theme_tag) AS theme,
    COALESCE(chat.contact_theme_detail_tag, call.contact_theme_detail_tag, email.contact_theme_detail_tag) AS theme_detail,
    COALESCE(chat.request_type, call.request_type, email.request_type) AS request_type,
    COALESCE(chat.customer_type_tag, call.customer_type_tag, email.customer_type_tag) AS customer_type_tag,
    COALESCE(chat.contact_motivation_tag, call.contact_motivation_tag, email.contact_motivation_tag) AS motivation,
    COALESCE(chat.front_or_back, call.front_or_back, email.front_or_back) AS front_or_back,
    csat.respondent_comments AS comment_csat,
    csat.improvement_tags AS csat_tags,
    csat.satisfaction_score AS csat_score,
    csat.secondary_satisfaction_score AS csat_partes,
    ri.has_chat_negociation,
    tfm.reopens,
    tfm.replies,
    rd.relisting,
    tfm.minutes_reply_calendar AS minutes_first_reply_time_calendar,
    c.dt_entered AS entrance_date,
    ri.definition_date,
    ri.ts_first_interaction,
    tf.ts_created_local,
    tf.ts_updated_local,
    tfm.ts_closed_local,
    tfm.ts_solved_local,
    rr.ts_created AS ts_request_created,
    CAST(csat.ts_submitted AS DATE) AS ts_csat_response_submitted,
    tfm.ts_initially_assigned_local,
    tfm.ts_last_assigned_local,
    YEAR(tf.ts_updated_local) AS year,
    MONTH(tf.ts_updated_local) AS month,
    DAY(tf.ts_updated_local) AS day
FROM 
    datalake_zendesk_ticket_funnels.ticket_funnel AS tf
LEFT JOIN 
    datalake_zendesk_ticket_funnels.tickets_funnel_metrics AS tfm 
        ON tf.id_ticket = tfm.id_ticket
LEFT JOIN 
    datalake_customer_support.chat AS chat
        ON tf.id_ticket = chat.id_ticket
LEFT JOIN 
    datalake_customer_support.call AS call
        ON tf.id_ticket = call.id_ticket
LEFT JOIN 
    datalake_customer_support.email AS email
        ON tf.id_ticket = email.id_ticket
LEFT JOIN 
    datalake_ebdb_contract.contract AS c
        ON tfm.id_contract = c.id
LEFT JOIN 
    datalake_repairs_clean.repair_request AS rr 
        ON tf.id_ticket = rr.id_third_party_crm_ticket_external
LEFT JOIN 
    repairs_interaction AS ri
        ON ri.id_request = rr.id
LEFT JOIN
    relisting_distinct AS rd
        ON rd.id_contract = tfm.id_contract
LEFT JOIN
    datalake_survicate.repairs_surveys AS csat
        ON csat.id_ticket = tf.id_ticket
WHERE 
    tf.group_name IN ('Reparos [BACK]','Triagem Reparos [Back]','FullService [BACK]','Autosserviço Reparos [BACK]') 
    AND (tf.ts_created >= DATE_ADD(CURRENT_DATE,-20*7) OR tfm.ts_solved >= date('2023-01-01') OR tfm.ts_solved IS NULL)
    AND tf.channel NOT IN ('call')
    AND tf.status NOT IN ('deleted')
    AND tf.tags NOT LIKE '%caso_ticket_agregador%'
    AND tf.id_ticket NOT IN (SELECT id_ticket FROM pp_tickets_test)
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY tf.id_ticket ORDER BY tf.ts_created_local DESC) = 1
