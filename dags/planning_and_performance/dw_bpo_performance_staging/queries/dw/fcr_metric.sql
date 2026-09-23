WITH fact_service AS (
    SELECT
        sk_event,
        sk_support_session,
        CAST(sk_support_session AS STRING) AS sk_support_session_varchar,
        bpo_name,
        queue_name AS fila_twilio,
        SUBSTR(theme, 3, LENGTH(theme) - 4) AS theme,
        SUBSTR(theme_detail, 3, LENGTH(theme_detail) - 4) AS theme_detail,
        ROW_NUMBER() OVER(PARTITION BY sk_support_session ORDER BY ts_task_created DESC, sk_task_event DESC) AS rn_task 
    FROM dw_support_journey.fact_services
     WHERE dt_task_created >= DATE('2026-06-25')
          AND is_current = true
          AND sk_support_session IS NOT NULL
          AND sk_support_session != '-1'
          AND queue_name not in ('IVR Events (no workers)')
),

customer_contacts AS (
    SELECT
        fcc.sk_interaction,
        fcc.sk_contact,
        fcc.sk_call,
        fcc.sk_session,
        fcc.sk_support_session,
        fcc.sk_ticket,
        fcc.sk_task,
        IF(fcc.sk_user = -1, ft.sk_user, fcc.sk_user) AS sk_user,
        fcc.sk_analyst,
        CASE 
            WHEN dd.department IN (
                '[AeC] CX Pagamentos [FRONT] [POS]',
                '[AeC] CX Ongoing [FRONT] [POS]',
                '[AeC] CX Rescisão [FRONT] [POS]', 
                '[AeC] CX Mudança [FRONT] [POS]', 
                '[AeC] CX Reparos [FRONT] [POS]', 
                '[AeC] CX Propostas [FRONT] [PRE]', 
                '[AeC] CX Visitas [FRONT] [PRE]', 
                '[AeC] CX Parceiros [FRONT] [PRE]', 
                '[AeC] Consultores imobiliários 5A', 
                '[AeC] CX Parceiros Compra e Venda [FRONT]'
            ) THEN SUBSTR(dd.department, 7) 
            ELSE dd.department
        END AS department,
      
        dd.area as area,
        dd.front_or_back as front_or_back,
        dd.team AS team,
        
         CASE
            WHEN dd.team IN (
                'Reparos - Autosserviço',
                'Reparos - Comum e Urgente',
                'Reparos - Emergencial',
                'Reparos - Reembolso',
                'Reparos - Contestação'
            ) THEN 'Reparos'
            WHEN dd.team IN (
                'Repairs/Ongoing Front',
                'Repairs/Ongoing Back',
                'Ongoing Back',
                'Ong Back',
                'Ongoing FR - Geral', 
                'Ongoing FR - Informe de Rendimentos'
            ) THEN 'Ongoing'
            WHEN dd.team IN (
                'Rental Manager',
                'Rental Manager Gold',
                'Rental Manager CTL'
            ) THEN 'Rental Manager'
            WHEN dd.team IN (
                'Payments',
                'Payments Ativo Back',
                'Payment FR - Reembolso de Condomínio', 
                'Payment FR - Condomínio Geral', 
                'Payment FR - Aluguel', 
                'Payment FR - PP Multi', 
                'Payment_FR_GeneralCondominium',
                'Payment FR - Dados Bancários',
                'Payment FR - Dados Bancários Front'
            ) THEN 'Payments'
            WHEN dd.team IN (
                'CX Partners',
                'CX Compra e Venda',
                'CX Partners For Sale'
            ) THEN 'Partners'
            WHEN dd.team IN (
                'Onboarding Back',
                'Moving',
                'Onboarding ForRent'
            ) THEN 'Onboarding'
            WHEN dd.team IN (
                'Offboarding Front',
                'Offboarding Back',
                'Offboarding - CNX',
                'Offboarding - AEC',
                'Offboarding - Atento'
            ) THEN 'Offboarding'
            WHEN dd.team IN (
                'ReclameAqui',
                'Privacy',
                'Casos Especiais',
                'PROCON',
                'Dados Bancários',
                'Conta Comigo',
                'Subsídios',
                'Consumidor.Gov',
                'Notificação Extrajudicial',
                'Midias Ops',
                'ReclameAqui - Grupo5A',
                'Reversão de NPS',
                'Escalados - consumidor.gov',
                'Escalados - Procon Reclamante',
                'Escalados - Mídias Sociais',
                'Escalados - Conta Comigo',
                'Escalados - Processo Cívil',
                'Escalados - Casos Esp Outros',
                'Escalados - Casos Esp Fraude',
                'Escalados - Casos Esp Int. Humana',
                'Escalados - Casos Esp Int. Imóvel',
                'Escalados - CC Colaboradores',
                'Escalados - Casos Especiais',
                'Escalados - Procon Subsídios',
                'Escalados - Reclame AQUI',
                'Escalados - Conta Comigo Entrada',
                'Escalados - CC Diretoria Ops'
            ) THEN 'CSI'
            ELSE dd.team
        END AS team_adjusted,
        
        da.email AS agent_email,
        da.agent_organization as agent_organization,

        fcc.origin                      AS origin_fcc,        
        fcc.channel,
        fcc.customer_email,
        fcc.is_interaction_answered,
        fcc.is_contact_answered,
        fcc.is_first_interaction,
        fcc.is_last_interaction,
        fcc.is_first_department_interaction,
        fcc.quinto_andar_phone_number,
        fcc.is_spoc_task,
        
        fcc.customer_phone_number AS customer_phone,
        fcc.is_per_team_task      AS per_team_flag,
        fcc.first_reply_time      AS first_response_time,
        UPPER(fcc.status)         AS status,
        fcc.direction,
        fcc.ts_reservation_created,
        fcc.ts_task_created,
        fcc.total_talk_time,
        fcc.total_handling_time,
        COALESCE(ft.ts_created, fcc.ts_task_created - INTERVAL 3 HOURS)       AS ts_created,
        COALESCE(DATE(ft.ts_created), DATE(fcc.ts_task_created - INTERVAL 3 HOURS)) AS dt_created,
        
        COALESCE(fs.theme, dt.theme) as theme,
        COALESCE(fs.theme_detail, dt.theme_detail) as theme_Detail,
        
       CASE 
    WHEN fcc.sk_ticket = -1 OR fcc.sk_ticket IS NULL THEN CAST(fcc.sk_support_session AS STRING)
    ELSE CAST(fcc.sk_ticket AS STRING)
END AS sk_session_key,

ROW_NUMBER() OVER(
    PARTITION BY CASE 
        WHEN fcc.sk_ticket = -1 OR fcc.sk_ticket IS NULL THEN CAST(fcc.sk_support_session AS STRING)
        ELSE CAST(fcc.sk_ticket AS STRING)
    END 
    ORDER BY fcc.ts_reservation_created DESC
) AS rn_task

    FROM dw_customer_support.fact_customer_contacts AS fcc
    LEFT JOIN dw_customer_support.dim_department AS dd       ON dd.sk_department = fcc.sk_department
    LEFT JOIN dw_customer_support.dim_analyst    AS da       ON da.sk_analyst = fcc.sk_analyst
    LEFT JOIN dw_customer_support.fact_tickets as ft on ft.sk_ticket = fcc.sk_ticket
    LEFT JOIN dw_customer_support.dim_taxonomy  as dt on dt.sk_taxonomy = ft.sk_taxonomy
    LEFT JOIN fact_service AS fs 
           ON fcc.sk_support_session = fs.sk_support_session_varchar AND fs.rn_task = 1
    WHERE 1 = 1
        AND fcc.ts_task_created >= DATE('2026-01-01')
        AND fcc.channel IN ('chat', 'call')
        AND fcc.origin NOT IN ('outbound')
),

cases_perspective as (
    SELECT 
        case_number,
        TRY_CAST(sk_user AS INT) AS sk_user,
        ts_started,
        ts_solved,
        last_agent_email,
        front_or_back,
            CASE
            WHEN last_team IN (
                'Reparos - Autosserviço',
                'Reparos - Comum e Urgente',
                'Reparos - Emergencial',
                'Reparos - Reembolso',
                'Reparos - Contestação'
            ) THEN 'Reparos'
            WHEN last_team IN (
                'Repairs/Ongoing Back',
                'Ongoing Back',
                'Ong Back',
                'Repairs/Ongoing Front',
                'Ongoing FR - Geral', 
                'Ongoing FR - Informe de Rendimentos'
            ) THEN 'Ongoing'
            WHEN last_team IN (
                'Rental Manager',
                'Rental Manager Gold',
                'Rental Manager CTL'
            ) THEN 'Rental Manager'
            WHEN last_team IN (
                'Payments',
                'Payments Ativo Back',
                'Payment FR - Reembolso de Condomínio', 
                'Payment FR - Condomínio Geral', 
                'Payment FR - Aluguel', 
                'Payment FR - PP Multi', 
                'Payment_FR_GeneralCondominium',
                'Payment FR - Dados Bancários',
                'Payment FR - Dados Bancários Front'
            ) THEN 'Payments'
            WHEN last_team IN (
                'CX Partners',
                'CX Compra e Venda',
                'CX Partners For Sale'
            ) THEN 'Partners'
            WHEN last_team IN (
                'Onboarding Back',
                'Onboarding ForRent',
                'Moving'
            ) THEN 'Onboarding'
            WHEN last_team IN (
                'Offboarding Front',
                'Offboarding Back',
                'Offboarding - CNX',
                'Offboarding - AEC',
                'Offboarding - Atento'
            ) THEN 'Offboarding'
            WHEN last_team IN (
                'ReclameAqui',
                'Privacy',
                'Casos Especiais',
                'PROCON',
                'Dados Bancários',
                'Conta Comigo',
                'Subsídios',
                'Consumidor.Gov',
                'Notificação Extrajudicial',
                'Midias Ops',
                'ReclameAqui - Grupo5A',
                'Reversão de NPS',
                'Escalados - consumidor.gov',
                'Escalados - Procon Reclamante',
                'Escalados - Mídias Sociais',
                'Escalados - Conta Comigo',
                'Escalados - Processo Cívil',
                'Escalados - Casos Esp Outros',
                'Escalados - Casos Esp Fraude',
                'Escalados - Casos Esp Int. Humana',
                'Escalados - Casos Esp Int. Imóvel',
                'Escalados - CC Colaboradores',
                'Escalados - Casos Especiais',
                'Escalados - Procon Subsídios',
                'Escalados - Reclame AQUI',
                'Escalados - Conta Comigo Entrada',
                'Escalados - CC Diretoria Ops'
            ) THEN 'CSI'
            ELSE last_team
        END AS team_adjusted,
        last_team,
        last_area,
        ROW_NUMBER() OVER(PARTITION BY case_number ORDER BY ts_load DESC) AS rn_case 
    FROM dw_bpo_performance_staging.cases_perspective as cp
    WHERE 1 = 1 
        AND ts_started >= date('2026-01-01') 
        AND TRY_CAST(sk_user AS INT) > 0 
        AND cp.last_area = 'CX'
        AND (cp.front_or_back in ('back','Back') OR cp.channel = 'whatsapp')
        AND cp.last_department NOT IN (
            'Welcome Onboarding [BACK] [POS]', 'CX Welcome Onboarding [FRONT][POS]', 'EARLY DEMAND [CLOSING] [BACK]',
            'FUP Carteirização B2C [CLO] [PRE] [BACK]', 'Closing Contratos [CLO] [PRE] [BACK]'
        )
),

back_penalizations as (
    SELECT 
        case_number,
        sk_user,
        ts_started,
        team_adjusted, 
        last_team,
        CASE
            WHEN cp.front_or_back in ('back','Back') THEN 1
            ELSE 0
        END AS flag_back
    FROM cases_perspective as cp
    WHERE rn_case = 1 
        AND cp.sk_user > 0 
)
        
, recontact_drilldown_per_bpo AS (

SELECT 
    sk_session_key,
    sk_user,
    team,
    sk_task AS original_sk_task,
    ts_created AS original_ts_started,
    agent_email AS original_agent_email,
    agent_organization AS original_agent_organization,

    LEAD(sk_session_key) OVER (
        PARTITION BY sk_user, team, theme, agent_organization
        ORDER BY ts_created
    ) AS recontact_sk_4sat_join_key,

    LEAD(sk_task) OVER (
        PARTITION BY sk_user, team, theme, agent_organization
        ORDER BY ts_created
    ) AS recontact_sk_task,

    LEAD(ts_created) OVER (
        PARTITION BY sk_user, team, theme, agent_organization
        ORDER BY ts_created
    ) AS recontact_ts_started,

    LEAD(agent_email) OVER (
        PARTITION BY sk_user, team, theme, agent_organization
        ORDER BY ts_created
    ) AS recontact_agent_email,

    LEAD(agent_organization) OVER (
        PARTITION BY sk_user, team, theme, agent_organization
        ORDER BY ts_created
    ) AS recontact_agent_organization,

    CAST(CASE WHEN is_first_interaction = TRUE THEN ts_created END AS DATE) AS ts_started,

    ------ SK TASK contato anterior
    LAG(sk_session_key) OVER (
        PARTITION BY sk_user, team
        ORDER BY ts_created
    ) AS prev_sk_task,

    ------ Data Contato Anterior    
    LAG(ts_created) OVER (
        PARTITION BY sk_user, team
        ORDER BY CAST(CASE WHEN is_first_interaction = TRUE THEN ts_created END AS DATE)
    ) AS prev_ts_started,

    ------ Agente Contato Anterior  
    LAG(agent_email) OVER (
        PARTITION BY sk_user, team
        ORDER BY ts_created
    ) AS prev_agent_email,

    ------ Organização Contato Anterior
    LAG(agent_organization) OVER (
        PARTITION BY sk_user, team
        ORDER BY ts_created
    ) AS prev_agent_organization,   

    ------ Theme Contato Anterior
    LAG(theme) OVER (
        PARTITION BY sk_user, team
        ORDER BY ts_created
    ) AS prev_theme_task,  

    -----------------------------------------
    -------- FLAG RECONTATO
    CASE
        -- 1. Verifica se o intervalo até o próximo contato é <= 4 dias
        WHEN DATEDIFF(
                CAST(LEAD(ts_created) OVER (
                    PARTITION BY sk_user, team, theme, agent_organization
                    ORDER BY ts_created ASC
                ) AS DATE),
                CAST(ts_created AS DATE)
             ) <= 4
        THEN CASE
                 -- 2. Garante que o recontato é em uma task/join_key diferente
                 WHEN sk_session_key != LEAD(sk_session_key) OVER (
                         PARTITION BY sk_user, team, theme, agent_organization
                         ORDER BY ts_created ASC
                      )
                  -- 3. Garante que não é a exata mesma interação (compara timestamps inteiros)
                  AND ts_created != LEAD(ts_created) OVER (
                         PARTITION BY sk_user, team, agent_organization
                         ORDER BY ts_created ASC
                      )
                  AND theme IS NOT NULL
                 THEN 1 ELSE 0
             END
        ELSE 0
    END AS theme_recontact_flag_bpo,

    ---- Recontato Flag Sem BPO
    CASE
        WHEN DATEDIFF(
                CAST(LEAD(ts_created) OVER (
                    PARTITION BY sk_user, team, theme
                    ORDER BY ts_created
                ) AS DATE),
                CAST(ts_created AS DATE)
             ) <= 4
        THEN CASE
                 WHEN sk_session_key != LEAD(sk_session_key) OVER (
                         PARTITION BY sk_user, team, theme
                         ORDER BY ts_created
                      )
                  AND ts_created != LEAD(ts_created) OVER (
                         PARTITION BY sk_user, team
                         ORDER BY ts_created
                      )
                  AND theme IS NOT NULL
                 THEN 1 ELSE 0
             END
        ELSE 0
    END AS theme_recontact_flag,

    -- Intervalo em Horas (Diferença em segundos / 3600)
    (
        CAST(LEAD(ts_created) OVER (
            PARTITION BY sk_user, team, theme, agent_organization
            ORDER BY ts_created
        ) AS LONG) - CAST(ts_created AS LONG)
    ) / 3600 AS recontact_interval_hours,

    -- Intervalo em Dias
    DATEDIFF(
        CAST(LEAD(ts_created) OVER (
            PARTITION BY sk_user, team, theme, agent_organization
            ORDER BY ts_created
        ) AS DATE),
        CAST(ts_created AS DATE)
    ) AS recontact_interval_days

FROM customer_contacts
WHERE rn_task = 1 

),
first_resolution as (
  SELECT 
    last_agent_email, 
    min (ts_solved) as first_resolution 
  FROM cases_perspective 
  GROUP BY 1 
),

pp_multi AS (
    SELECT
        dt_houses_owned as date,
        id_owner as sk_owner,
        ongoing_houses,
        is_pp_multi_active,
        CASE WHEN is_pp_multi_active = TRUE or ongoing_houses >= 5 THEN TRUE ELSE FALSE END AS is_pp_multi
    FROM datalake_pro_owners.daily_owner_houses_quantity_history ppm
    WHERE (ongoing_houses >= 5 OR  is_pp_multi_active = TRUE)
)

SELECT DISTINCT
    cc.sk_session_key as sk_session_and_ticket,
    cc.sk_ticket,
    ts_created as ts_started,
    cc.sk_user,
    cc.channel,
    cc.team as last_team,
    cc.department as last_department,
    cc.front_or_back,
    cc.agent_organization as last_agent_organization, 
    flag_back,
    cc.origin_fcc,
    cc.direction,
    theme_recontact_flag,
    theme_recontact_flag_bpo as theme_recontact_flag_per_bpo,
    ppm.is_pp_multi,
    cc.agent_email as last_agent_email,
    fr.first_resolution as first_resolution_last_agent,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day,
    NOW() AS ts_load
FROM customer_contacts AS cc
LEFT JOIN recontact_drilldown_per_bpo AS rd ON rd.sk_session_key = cc.sk_session_key
LEFT JOIN back_penalizations AS bpe
        ON cc.sk_user = bpe.sk_user
       AND cc.team_adjusted   = bpe.team_adjusted
       AND cc.ts_created      <= bpe.ts_started
       AND datediff(DATE(bpe.ts_started), DATE(cc.ts_created)) <= 4
LEFT JOIN pp_multi as ppm on ppm.sk_owner = cc.sk_user and DATE(CASE WHEN is_first_interaction = TRUE THEN ts_created END) = ppm.date
LEFT JOIN first_resolution AS fr ON fr.last_agent_email = cc.agent_email
WHERE rn_task = 1
 AND DATE(ts_created) <= date_add(current_date(), -4)
 AND cc.direction = 'inbound'
 AND cc.sk_user > 0
 AND cc.sk_user IS NOT NULL
 AND cc.department IN (
            'CX Mudança [FRONT] [POS]', 'CX Parceiros Compra e Venda [FRONT]', 'CX Parceiros [FRONT] [PRE]',
            'CX Parceiros da Portaria [FRONT] [PRE]', 'CX Propostas [FRONT] [PRE]', 'CX Visitas [FRONT] [PRE]',
            'Consultores imobiliários 5A', 'CX Pagamentos [FRONT] [POS]', 'CX Reparos [FRONT] [POS]',
            'CX Rescisão [FRONT] [POS]', 'CX Visitas N1 & N2 [VIS] [PRE] [FRONT] [OUT]', 'CX PROPOSTAS CALL/CHAT [PRO][PRE][FRONT]',
            'CX Plaquinhas [FRONT] [PRE]', 'CX Entrada no imóvel [ONB] [POS] [FRONT]', 'CX Pagamentos N1 [PAY] [POS] [FRONT]',
            'CX Durante a locação e reparos [POS] [FRONT]', 'CX Rescisão e Vistoria [OFF] [POS] [FRONT]', '[WH] Credito [FRONT]',
            '[WH] Closing [FRONT]', '[AeC] CX Pagamentos [FRONT] [POS]', '[AeC] CX Rescisão [FRONT] [POS]',
            '[AeC] CX Mudança [FRONT] [POS]', '[AeC] CX Reparos [FRONT] [POS]', '[AeC] CX Propostas [FRONT] [PRE]',
            '[AeC] CX Visitas [FRONT] [PRE]', '[AeC] CX Parceiros [FRONT] [PRE]', '[AeC] CX Ongoing [FRONT] [POS]',
            'CX Ongoing [FRONT] [POS]', '[AeC] Consultores imobiliários 5A', '[AeC] CX Parceiros Compra e Venda [FRONT]',
    '[WH] CX Propostas [FRONT] [PRE]'
        )


