WITH ticket_iq  as (
    SELECT DISTINCT
        ft.sk_ticket,
        client_type,
        sr.id_repair_request AS id_request
    FROM 
        dw_tickets.fact_tickets AS ft
    LEFT JOIN 
        dw_tickets.dim_ticket AS dt 
            ON dt.sk_ticket = ft.sk_ticket
    LEFT JOIN 
        datalake_repairs_clean.service_request AS sr 
            ON sr.id_third_party_crm_ticket_external = ft.sk_ticket
    WHERE 
        dt.tags LIKE '%teste_ps_pp_grupo_b_intermediacao_autosservico%'
),
pp_tickets_test AS (
    SELECT 
        tkt.sk_ticket
    FROM 
        ticket_iq
    INNER JOIN 
        datalake_repairs_clean.service_request AS req 
            ON req.id_repair_request = ticket_iq.id_request 
    INNER JOIN 
        dw_tickets.dim_ticket AS tkt 
            ON tkt.sk_ticket = req.id_third_party_crm_ticket_external
),
relisting_db AS (
    SELECT DISTINCT
        dc.sk_contract,
        CASE 
            WHEN (dhl.ts_publication  IS NOT NULL) THEN dhl.sk_house_listing 
            ELSE NULL 
        END AS listing
    FROM 
        dw_public.fact_listing_rent_flows AS fact_listing_rent_flows
    FULL JOIN 
        dw_public.dim_house_listing AS dhl 
            ON fact_listing_rent_flows.sk_house_listing = dhl.sk_house_listing 
    LEFT JOIN 
        dw_public.dim_contract AS dc 
            ON fact_listing_rent_flows.sk_contract = dc.sk_contract
    WHERE 
        DATE_TRUNC('month',dhl.ts_listing_version_start) >= ADD_MONTHS(DATE_TRUNC('month',CURRENT_DATE),-47)
        AND DATE_TRUNC('month',dhl.ts_listing_version_start) <= DATE_ADD(CURRENT_DATE, -1)
        AND (dhl.listing_category_start = 'Re-Listing') 
        AND ((dhl.country_code <> 'MX') OR (dhl.country_code IS NULL))
),
relisting_distinct AS (
    SELECT
        sk_contract,
        COUNT(DISTINCT listing) AS relisting
    FROM
        relisting_db
    WHERE
        sk_contract <> -1
    GROUP BY 1
)
SELECT 
    ft.sk_ticket,
    ft.sk_contract,
    rr.id AS sk_request,
    dt.group_name,
    dt.client_type,
    dt.status,
    dt.custom_fields,
    ft.agent_email,
    ft.reopens,
    dt.tags,
    dt.ticket_via,
    dt.channel,
    ft.minutes_first_reply_time_calendar,
    rd.relisting,
    da.email,
    da.agent_organization,
    ft.replies,
    rr.service_provider,
    tax.theme,
    tax.theme_detail,
    tax.request_type,
    tax.customer_type_tag,
    tax.motivation,
    cs.front_or_back,
    csat.csat_score,
    CAST(dc.dt_entrance AS DATE) AS entrance_date,
    CAST(dt.ts_created_local AS DATE) AS created_date,
    CAST(ft.ts_solved_local AS DATE) AS solved_date,
    CAST(rr.ts_created AS DATE) request_date,
    CAST(csat.ts_first_response AS DATE) AS csat_response_date,
    ft.ts_updated_local,
    ft.ts_last_assigned_local,
    ft.ts_initially_assigned_local,
    ft.ts_closed_local,
    YEAR(CURRENT_DATE - 1) AS year,
    MONTH(CURRENT_DATE - 1) AS month,
    DAY(CURRENT_DATE - 1) AS day
FROM 
    dw_tickets.fact_tickets AS ft
LEFT JOIN 
    dw_tickets.dim_ticket AS dt 
        ON dt.sk_ticket = ft.sk_ticket
LEFT JOIN 
    dw_public.dim_contract AS dc 
        ON ft.sk_contract = dc.sk_contract
LEFT JOIN 
    dw_customer_support.fact_ticket AS cs
        ON cs.sk_ticket = ft.sk_ticket
LEFT JOIN
    dw_customer_support.dim_agent AS da
        ON ft.sk_agent = da.sk_agent
LEFT JOIN 
    dw_customer_support.dim_taxonomy AS tax
        ON tax.sk_taxonomy = cs.sk_taxonomy
LEFT JOIN 
    datalake_repairs_clean.repair_request AS rr 
        ON rr.id_third_party_crm_ticket_external = ft.sk_ticket
LEFT JOIN
    relisting_distinct AS rd
        ON rd.sk_contract = ft.sk_contract
LEFT JOIN
    datalake_survicate.zendesk_email_surveys AS csat
        ON csat.id_ticket = ft.sk_ticket
WHERE 
    dt.group_name IN ('Reparos [BACK]','Triagem Reparos [Back]') 
    AND (dt.ts_created >= DATE_ADD(CURRENT_DATE,-20*7) OR ft.ts_solved >= date('2023-01-01') OR ft.ts_solved IS NULL)
    AND dt.channel NOT IN ('call')
    AND dt.status NOT IN ('deleted')
    AND dt.tags NOT LIKE '%caso_ticket_agregador%'
    AND ft.sk_ticket NOT IN (SELECT sk_ticket FROM pp_tickets_test)
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY ft.sk_ticket ORDER BY dt.ts_created_local DESC) = 1