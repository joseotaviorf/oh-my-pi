WITH 
universo_tickets AS (
    SELECT 
        TRY_CAST(bmt.sk_task AS BIGINT) AS sk_task,
        ft.sk_user,
        bmt.sk_agent, 
        tickets.sk_last_analyst,
        dd.department,
        NULLIF(ft.sk_contract, -1) AS sk_contract_ticket,
        bmt.status AS status_real,
        'BACKLOG_ATIVO' AS categoria_origem
    FROM dw_customer_support.fact_backlog_metrics_tasks bmt
    INNER JOIN dw_customer_support.dim_department dd 
        ON bmt.sk_main_department = dd.sk_department
    LEFT JOIN dw_customer_support.fact_tickets ft 
        ON TRY_CAST(bmt.sk_task AS BIGINT) = ft.sk_ticket
    LEFT JOIN dw_customer_support.fact_tickets AS tickets
        ON bmt.sk_task = CAST(tickets.sk_ticket AS varchar(99))
    WHERE bmt.dt_metric_reference = CURRENT_DATE - INTERVAL '1' DAY
      AND bmt.origin = 'email'
      AND (bmt.status IS NULL OR bmt.status IN ('open', 'new', 'hold', 'pending'))
      AND dd.department IN ('CX Pagamentos Ativo [POS] [BACK] [PAY]',
      'CX Alteração de dados bancários [BACK] [POS] [PAY] [WH]',
      'CX Onboarding [BACK] [POS] [WH]',
      'Aditivos [POS] [BACK] [WH]',
      'CX Propostas Tarefas [PRE] [BACK]',
      'Atendimento Escalado [OFF] [POS] [BACK]')

    UNION ALL

    SELECT 
        TRY_CAST(bmt.sk_task AS BIGINT) AS sk_task,
        ft.sk_user,
        bmt.sk_agent, 
        ft.sk_last_analyst,
        dd.department,
        NULLIF(ft.sk_contract, -1) AS sk_contract_ticket,
        'solved' AS status_real,
        'RECEM_RESOLVIDO' AS categoria_origem
    FROM dw_customer_support.fact_backlog_metrics_tasks bmt
    INNER JOIN dw_customer_support.dim_department dd 
        ON bmt.sk_main_department = dd.sk_department
    INNER JOIN dw_customer_support.fact_tickets ft 
        ON TRY_CAST(bmt.sk_task AS BIGINT) = ft.sk_ticket 
        AND ft.ts_solved >= CURRENT_DATE - INTERVAL '3' DAY
    WHERE bmt.dt_metric_reference = CURRENT_DATE - INTERVAL '3' DAY
      AND bmt.origin = 'email'
      AND (bmt.status IS NULL OR bmt.status IN ('open', 'new', 'hold', 'pending'))
      AND dd.department IN ('CX Pagamentos Ativo [POS] [BACK] [PAY]',
      'CX Alteração de dados bancários [BACK] [POS] [PAY] [WH]',
      'CX Onboarding [BACK] [POS] [WH]',
      'Aditivos [POS] [BACK] [WH]',
      'CX Propostas Tarefas [PRE] [BACK]',
      'Atendimento Escalado [OFF] [POS] [BACK]')
),

backlog_text_extract AS (
    SELECT 
        dit.sk_ticket AS sk_task,
        TRY_CAST(REGEXP_EXTRACT(dit.custom_fields, '"ID do ticket vinculado":"(\d+)"', 1) AS BIGINT) AS id_ticket_vinculado,
        TRY_CAST(REGEXP_EXTRACT(dit.custom_fields, 'Código do Imóvel.*?:.*?(\d+)', 1) AS BIGINT) AS id_house_texto
    FROM 
        dw_customer_support.dim_ticket dit
    WHERE 
        dit.sk_ticket IN (SELECT sk_task FROM universo_tickets)
),
lista_usuarios AS (
    SELECT DISTINCT 
        sk_user 
    FROM 
        universo_tickets 
    WHERE 
        sk_user > 0
    ),
lista_tickets_target AS (
    SELECT DISTINCT 
        id_ticket_vinculado 
    FROM 
        backlog_text_extract bte
    WHERE  
        id_ticket_vinculado IS NOT NULL
    ),
lista_houses_target AS (
    SELECT DISTINCT
        id_house_texto 
    FROM 
        backlog_text_extract 
    WHERE 
        id_house_texto IS NOT NULL
    ),
active_listings_roots AS (
    SELECT 
        sk_house_listing,
        CAST(sk_house_listing / 1000 AS BIGINT) AS root_key,
        sk_contract
    FROM dw_rent.fact_house_listings
    WHERE sk_contract > 0 
      AND CAST(sk_house_listing / 1000 AS BIGINT) IN (SELECT id_house_texto FROM lista_houses_target)
),
flag_regra_1_5 AS (
    SELECT t.sk_ticket, t.sk_contract
    FROM dw_customer_support.fact_tickets t
    WHERE t.sk_ticket IN (SELECT id_ticket_vinculado FROM lista_tickets_target)
      AND t.sk_contract > 0
),
flag_regra_2 AS (
    SELECT fhl.sk_owner, MIN(fhl.sk_contract) as sk_contract
    FROM dw_rent.fact_house_listings fhl
    WHERE fhl.sk_owner IN (SELECT sk_user FROM lista_usuarios)
      AND fhl.sk_contract > 0
    GROUP BY 1
),
flag_regra_2_5 AS (
    SELECT bte.sk_task, MIN(alr.sk_contract) as sk_contract
    FROM backlog_text_extract bte
    INNER JOIN active_listings_roots alr ON bte.id_house_texto = alr.root_key
    GROUP BY 1
),
flag_regra_3 AS (
    SELECT fcp.sk_user, fcp.sk_contract
    FROM dw_rent.fact_contract_people fcp
    INNER JOIN dw_rent.dim_contract dc ON fcp.sk_contract = dc.sk_contract
    WHERE fcp.sk_user IN (SELECT sk_user FROM lista_usuarios)
      AND dc.status IN ('Ativo', 'Finalizado')
),
tabela_base AS (
    SELECT 
        u.*,
        COALESCE(u.sk_contract_ticket, r15.sk_contract, r2.sk_contract, r25.sk_contract) AS contrato_prioritario,
        CASE 
            WHEN u.sk_contract_ticket IS NOT NULL THEN '1. Regra 1: Contrato do Ticket'
            WHEN r15.sk_contract IS NOT NULL THEN '1.5. Regra 1.5: Ticket Vinculado'
            WHEN r2.sk_contract IS NOT NULL THEN '2. Regra 2: Owner (Vínculo Direto)'
            WHEN r25.sk_contract IS NOT NULL THEN '2.5. Regra 2.5: Fallback Texto'
            ELSE NULL 
        END AS regra_prioritaria,
        CASE 
            WHEN COALESCE(u.sk_contract_ticket, r15.sk_contract, r2.sk_contract, r25.sk_contract) IS NULL 
            THEN 1 ELSE 0 
        END AS flag_usar_regra_3
    FROM universo_tickets u
    LEFT JOIN backlog_text_extract bte ON u.sk_task = bte.sk_task
    LEFT JOIN flag_regra_1_5 r15 ON bte.id_ticket_vinculado = r15.sk_ticket
    LEFT JOIN flag_regra_2 r2 ON u.sk_user = r2.sk_owner
    LEFT JOIN flag_regra_2_5 r25 ON u.sk_task = r25.sk_task
)
SELECT 
    tb.sk_task AS sk_task,
    tb.department AS department,
    da_last.email AS analyst_email,
    CASE
        WHEN da_last.agent_organization = 'atn' THEN 'atento'
        WHEN da_last.agent_organization = 'atento' THEN 'atento'
        WHEN da_last.agent_organization = 'webhelp' THEN 'webhelp'
        WHEN da_last.agent_organization = 'webhelpbr' THEN 'webhelp'
        WHEN da_last.agent_organization = 'quintoandar.com' THEN 'quintoandar'
        WHEN da_last.agent_organization = 'quintoandar' THEN 'quintoandar'
        WHEN da_last.agent_organization = 'contractors' THEN 'webhelp'
        WHEN da_last.agent_organization IS NULL THEN 'Ticket ainda não atribuído'
        ELSE da_last.agent_organization
    END AS agent_organization,
    COALESCE(tb.regra_prioritaria, 
             CASE WHEN r3.sk_contract IS NOT NULL THEN '3. Regra 3: Multi-Contrato' ELSE '4. Sem Contrato Identificado' END
    ) AS contract_identification_rule,
    COALESCE(tb.contrato_prioritario, r3.sk_contract) AS sk_contract,
    tb.sk_user,
    CASE 
        WHEN fcp.contract_role = 'landlord' THEN 'PP'
        WHEN fcp.contract_role = 'tenant' THEN 'IQ'
        WHEN COALESCE(tb.contrato_prioritario, r3.sk_contract) IS NOT NULL THEN 'Outro'
        ELSE NULL 
    END AS user_type,
    CASE 
        WHEN tb.categoria_origem = 'RECEM_RESOLVIDO' THEN 'fechado + 3 dias'
        WHEN tb.status_real IN ('new', 'open') THEN 'aberto'
        WHEN tb.status_real = 'hold' THEN 'em espera'
        WHEN tb.status_real = 'pending' THEN 'pendente'
        WHEN tb.status_real = 'solved' THEN 'fechado'
        ELSE tb.status_real 
    END AS ticket_status,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day,
    NOW() AS ts_load
FROM tabela_base tb
LEFT JOIN flag_regra_3 r3 
    ON tb.sk_user = r3.sk_user 
    AND tb.flag_usar_regra_3 = 1
LEFT JOIN dw_customer_support.dim_analyst AS da_last 
    ON da_last.sk_analyst = tb.sk_last_analyst
LEFT JOIN dw_rent.fact_contract_people fcp 
    ON COALESCE(tb.contrato_prioritario, r3.sk_contract) = fcp.sk_contract 
    AND tb.sk_user = fcp.sk_user
    AND fcp.is_user = true
WHERE da_last.agent_organization IN ('webhelp', 'webhelpbr') 