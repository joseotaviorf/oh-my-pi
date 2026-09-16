WITH terminator_enriched AS (
    SELECT
        ft.sk_termination,
        TRY_CAST(ft.is_spoc_eligible AS boolean)           AS is_spoc_eligible,
        COALESCE(ft.is_spoc_contract, false)                AS is_spoc,
        dc.sk_contract,
        dc.status,
        CAST(fc.sk_tenant AS string)                        AS sk_tenant,
        CAST(fc.sk_owner AS string)                         AS sk_owner,
        ft.ts_termination_request                           AS ts_offboarding_start,
        ft.ts_termination_finished,
        COALESCE(obt.has_mediation_ticket, false)           AS is_mediacao,
        obt.has_repairs
    FROM dw_offboarding.fact_terminations AS ft
    LEFT JOIN dw_rent.dim_contract AS dc
        ON ft.sk_contract = dc.sk_contract
    LEFT JOIN dw_rent.fact_contracts AS fc
        ON fc.sk_contract = dc.sk_contract
    LEFT JOIN dw_offboarding.obt_offboarding AS obt
        ON obt.sk_contract = dc.sk_contract
        AND obt.sk_termination = ft.sk_termination
    WHERE
        CAST(ft.ts_termination_finished AS DATE) >= DATE'2026-01-01'
),

departments AS (
    SELECT
        sk_department,
        department,
        team
    FROM dw_customer_support.dim_department
),

first_department AS (
    SELECT
        fcc.sk_ticket,
        COALESCE(
            NULLIF(CAST(fcc.sk_session AS STRING), '-1'),
            NULLIF(fcc.sk_support_session, '-1')
        )                                                   AS sk_support_session_fallback_sk_session,
        fcc.channel                                          AS channel,
        dd.department                                        AS first_department,
        dd.team                                               AS first_team,
        ROW_NUMBER() OVER (
            PARTITION BY COALESCE(
                NULLIF(CAST(fcc.sk_session AS STRING), '-1'),
                NULLIF(fcc.sk_support_session, '-1')
            )
            ORDER BY fcc.ts_task_created ASC
        )                                                     AS rn
    FROM dw_customer_support.fact_customer_contacts fcc
    LEFT JOIN departments dd
        ON dd.sk_department = fcc.sk_department
    WHERE fcc.is_first_interaction = TRUE
        AND fcc.ts_task_created >= TIMESTAMP'2025-01-01 00:00:00'
),

segments AS (
    SELECT
        fcc.ts_task_created - INTERVAL '3' HOUR              AS ts_created,
        fcc.sk_user,
        fcc.channel,
        dd.department,
        fcc.sk_ticket,
        COALESCE(
            NULLIF(CAST(fcc.sk_session AS STRING), '-1'),
            NULLIF(fcc.sk_support_session, '-1')
        )                                                     AS sk_support_session_fallback_sk_session
    FROM dw_customer_support.fact_customer_contacts fcc
    LEFT JOIN departments dd
        ON dd.sk_department = fcc.sk_department
    LEFT JOIN first_department fd
        ON fd.sk_support_session_fallback_sk_session = COALESCE(
            NULLIF(CAST(fcc.sk_session AS STRING), '-1'),
            NULLIF(fcc.sk_support_session, '-1')
        )
        AND fd.rn = 1
    WHERE fcc.ts_task_created >= TIMESTAMP'2025-01-01 00:00:00'
        AND fcc.channel IN ('chat', 'call')
        AND fcc.is_interaction_answered = TRUE
),

front_tickets_segments_perspective AS (
    SELECT DISTINCT
        CAST(seg.sk_user AS string)                          AS sk_user,
        CAST(seg.ts_created AS timestamp)                    AS ts_ticket_started,
        CAST(seg.sk_support_session_fallback_sk_session AS string) AS sk_ticket,
        -1                                                     AS sk_contract_ticket,
        CAST(NULL AS string)                                  AS tipo_ticket,
        seg.department                                        AS last_department,
        seg.channel                                            AS channel,
        0                                                       AS replies,
        'Front'                                                AS front_or_back,
        CAST(NULL AS string)                                  AS platform,
        CASE
            WHEN seg.department IN ('[AeC] CX Mudança [FRONT] [POS]', 'CX Mudança [FRONT] [POS]') THEN 'Onboarding'
            WHEN seg.department IN ('[AeC] CX Pagamentos [FRONT] [POS]', '[WH] Alteração de dados bancários [Front]', 'CX Pagamentos [FRONT] [POS]', 'OPS COBRANÇA ATIVO [POS]') THEN 'Payments'
            WHEN seg.department IN ('[AeC] CX Reparos [FRONT] [POS]', 'CX Reparos [FRONT] [POS]') THEN 'Reparos'
            WHEN seg.department IN ('[AeC] CX Ongoing [FRONT] [POS]') THEN 'Ongoing'
            WHEN seg.department IN ('[AeC] CX Rescisão [FRONT] [POS]', 'CX Rescisão [FRONT] [POS]') THEN 'Offboarding'
            ELSE 'Outros'
        END                                                     AS team
    FROM segments seg
    WHERE TRY_CAST(seg.sk_user AS bigint) > 0
        AND seg.department IN (
            '[WH] Alteração de dados bancários [Front]',
            '[AeC] CX Mudança [FRONT] [POS]',
            '[AeC] CX Reparos [FRONT] [POS]',
            '[AeC] CX Ongoing [FRONT] [POS]',
            'CX Mudança [FRONT] [POS]',
            'CX Pagamentos [FRONT] [POS]',
            'CX Reparos [FRONT] [POS]',
            'CX Rescisão [FRONT] [POS]',
            'OPS COBRANÇA ATIVO [POS]',
            '[AeC] CX Pagamentos [FRONT] [POS]',
            '[AeC] CX Rescisão [FRONT] [POS]'
        )
),

salesforce_cases_perspective AS (
    SELECT DISTINCT
        cp.sk_user,
        cp.ts_started                                          AS ts_ticket_started,
        CAST(cp.case_number AS STRING)                        AS sk_ticket,
        COALESCE(TRY_CAST(cp.sk_contract AS BIGINT), -1)      AS sk_contract_ticket,
        cp.theme                                                AS tipo_ticket,
        last_department,
        cp.channel,
        COALESCE(TRY_CAST(cp.replies AS integer), 0)          AS replies,
        'Back'                                                  AS front_or_back,
        CAST(cp.platform AS string)                            AS platform,
        CASE
            WHEN last_department IN ('Onboarding ForRent')
                OR last_department IN ('Entrada no imóvel [ONB] [POS] [BACK]', 'Welcome Onboarding [BACK] [POS]', 'CX Entrada no imóvel [ONB] [POS] [FRONT]') THEN 'Onboarding'
            WHEN last_department IN ('Payment FR - Condomínio Interno', 'Payment FR - PP Multi', 'Payment FR - Dados Bancários', 'Payment FR - Aluguel', 'Payment FR - Condomínio Geral', 'Payment FR - Reembolso de Condomínio', 'Payment FR - Dados Bancários Front', 'Payment_FR_GeneralCondominium', 'Onboarding/Offboarding - Ajustes em Contas de Consumo')
                OR last_department IN ('Ops Cobrança [BACK] [POS]', 'CX Pagamentos Ativo [POS] [BACK] [PAY]', 'Alteração de dados bancários [BACK]', 'CX Pagamentos N1 [PAY] [POS] [FRONT]', 'AeC - CX Pagamentos N1 [PAY] [POS] [FRONT]') THEN 'Payments'
            WHEN last_department IN ('Ongoing FR - Geral', 'Ongoing FR - Informe de Rendimentos', 'Ongoing - Intermediações simples e acordos')
                OR last_department IN ('Aditivos [REP] [POS] [BACK]') THEN 'Ongoing'
            WHEN last_department IN ('Item de Reparo', 'Reparos - Autosserviço', 'Reparos - Comum e Urgente', 'Reparos - Emergencial', 'Reparos - Reembolso', 'Reparos - Contestação', 'Reembolso de Reparos', 'Reparos - PPMulti', 'Reparos Ongoing', 'Solicitação de Reparos', 'Reparos - Contestação de responsibillidade ou criticidade')
                OR last_department IN ('Reembolso de Reparos [Back]', 'Reparos [BACK]', 'Autosserviço Reparos [BACK]', 'FullService [BACK]', 'Triagem Reparos [Back]', 'ReparAção (Piloto Urgente)', 'ReparAção Comum [BACK]', 'Reparos PP Multi [BACK]', 'Reparos [REP] [POS] [BACK]', 'Triagem [Porto]', 'Atendimento [Porto]', 'ReparAção Emergencial [BACK]') THEN 'Reparos'
            WHEN last_department IN ('Collections FR - Cobrança de primeiro boleto', 'Collections Backoffice', 'Collections Backoffice FPD e PP', 'Collections Backoffice - Correções ou reembolso de contas e caução', 'Collections FR - Suporte ao Proprietário', 'Collections FR - Cob. Primeiro Boleto', 'Collections FR PP - Cobrança Prop')
                OR last_department IN ('Backoffice Proprietários [COL] [BACK]', 'Cobrança 0-30d [COL] [POS] [BACK]', 'Cobrança Acordos [COL] [POS] [BACK]', 'Cobrança 31-60d [COL] [POS] [BACK]', 'Cobrança Proprietários [COL] [POS] [BACK]') THEN 'Collections'
            WHEN last_department IN ('Offboarding - CNX', 'Offboarding - AEC', 'Offboarding - Atento', 'Offboarding - Dados Bancários', 'Offboarding For Rent', 'Offboarding - Finalização de contrato', 'Offboarding - Pagamentos, condominio e multa rescisória')
                OR last_department IN ('CX Off Manager [SPOC]', 'Atendimento Escalado [OFF] [POS] [BACK]', 'Fluxo de Exceção - Constatação [OFF] [POS] [BACK]') THEN 'Offboarding'
            WHEN last_department IN ('RA Offboarding', 'RA Ongoing e ForSale', 'Reclame Aqui', 'Escalados - Casos Esp Int. Humana', 'Escalados - Mídias Sociais', 'Escalados - Casos Esp Int. Imóvel', 'Escalados - Casos Esp Fraude', 'Escalados - Casos especiais', 'Escalados - Processo Cívil', 'Escalados - Canais Externos', 'Escalados - Procon Reclamante', 'Escalados - Casos Esp Outros', 'Escalados - Casos Especiais')
                OR last_department LIKE '%Escalados -%'
                OR last_department IN ('CX Conta Comigo [POS] [BACK]', 'Consumidor.Gov [CE] [POS] [BACK]', 'Casos Especiais [CE] [POS] [BACK]', 'PROCON [CE] [POS] [BACK]', 'Midias Ops [POS] [BACK]', 'Subsídios de Processos [CE] [POS] [BACK]', 'Notificação Extrajudicial [CE] [POS] [BACK]', 'Privacy [CE] [POS] [BACK]') THEN 'CSI'
            WHEN last_department IN ('Logística de Chaves - For Rent', 'For Rent - Chaves Emergencial', 'Chaves - Magic Link', 'Logística de chaves - Offboarding', 'Logística de Chaves - For Rent - Front', 'Logística de chaves - Onboarding')
                OR last_department IN ('Solicitação de Movimentação Chaves [Corridas] [SO]', 'Logística Chaves Onboarding [SO]', 'Lockbox - Pedidos da FAQ [SO]', 'Logística Chaves Offboarding [SO]') THEN 'Chaves'
            WHEN last_department IN ('Vistorias - Constatação', 'Vistorias - Reagendamento Off', 'Vistorias - Reagendamento Onb', 'Reagendamento de Vistoria')
                OR last_department IN ('Agendamento Vistoria Entrada [SO]', 'Agendamento Vistoria Saída [SO]', 'Agendamento de Vistoria RS [VT] [OFF] [RS]') THEN 'Vistorias'
            ELSE 'Outros'
        END                                                     AS team
    FROM dw_bpo_performance.cases_perspective AS cp
    WHERE 1 = 1
        AND LOWER(cp.channel) LIKE '%email%'
        AND COALESCE(TRY_CAST(cp.replies AS integer), 0) >= 1
),

tickets_raw AS (
    SELECT sk_user, ts_ticket_started, sk_ticket, sk_contract_ticket, tipo_ticket, last_department, channel, replies, front_or_back, platform, team
    FROM front_tickets_segments_perspective

    UNION ALL

    SELECT sk_user, ts_ticket_started, sk_ticket, sk_contract_ticket, tipo_ticket, last_department, channel, replies, front_or_back, platform, team
    FROM salesforce_cases_perspective
),

deduplicated_tickets AS (
    SELECT
        t.sk_ticket,
        t.sk_user,
        t.ts_ticket_started,
        t.sk_contract_ticket,
        t.tipo_ticket,
        t.last_department,
        t.channel,
        t.replies,
        t.front_or_back,
        t.platform,
        t.team,
        ROW_NUMBER() OVER (ORDER BY t.sk_ticket)                AS unique_row_id
    FROM (
        SELECT sk_ticket, sk_user, ts_ticket_started, sk_contract_ticket, tipo_ticket, last_department, channel, replies, front_or_back, platform, team
        FROM tickets_raw
        WHERE front_or_back = 'Front' OR (front_or_back = 'Back' AND LOWER(COALESCE(platform, '')) = 'salesforce')
 
        UNION ALL
 
        SELECT
            sk_ticket,
            MAX(sk_user)             AS sk_user,
            MAX(ts_ticket_started)   AS ts_ticket_started,
            MAX(sk_contract_ticket)  AS sk_contract_ticket,
            MAX(tipo_ticket)         AS tipo_ticket,
            MAX(last_department)     AS last_department,
            MAX(channel)             AS channel,
            MAX(replies)             AS replies,
            MAX(front_or_back)       AS front_or_back,
            MAX(platform)            AS platform,
            MAX(team)                AS team
        FROM tickets_raw
        WHERE front_or_back = 'Back' AND LOWER(COALESCE(platform, '')) != 'salesforce'
        GROUP BY sk_ticket
    ) t
),

chatbot_by_user AS (
    SELECT
        CAST(fsc.id_user AS bigint)                            AS sk_user,
        fsc.ts_created                                          AS enriched_ts
    FROM datalake_chatbot.sessions fsc
    WHERE CAST(fsc.id_user AS bigint) > 0
        AND fsc.ts_created >= DATE'2026-01-01'
        AND fsc.bot IN ('wall-e', 'old bot')
),

matched_by_contract AS (
    SELECT
        exploded.sk_termination,
        exploded.is_spoc_eligible,
        exploded.is_spoc,
        exploded.sk_contract,
        exploded.status,
        exploded.sk_tenant,
        exploded.sk_owner,
        exploded.ts_offboarding_start,
        exploded.ts_termination_finished,
        exploded.is_mediacao,
        exploded.has_repairs,
        exploded.sk_ticket,
        exploded.tipo_ticket,
        exploded.ts_ticket_started,
        exploded.last_department,
        exploded.channel,
        exploded.replies,
        exploded.front_or_back,
        exploded.platform,
        exploded.team,
        exploded.unique_row_id,
        (cb.sk_user IS NOT NULL)                               AS is_chatbot
    FROM (
        SELECT
            te.sk_termination,
            te.is_spoc_eligible,
            te.is_spoc,
            te.sk_contract,
            te.status,
            te.sk_tenant,
            te.sk_owner,
            te.ts_offboarding_start,
            te.ts_termination_finished,
            te.is_mediacao,
            te.has_repairs,
            t.sk_ticket,
            t.tipo_ticket,
            t.ts_ticket_started,
            t.last_department,
            t.channel,
            t.replies,
            t.front_or_back,
            t.platform,
            t.team,
            t.unique_row_id,
            u.sk_user_key
        FROM terminator_enriched AS te
        JOIN deduplicated_tickets AS t
            ON te.sk_contract = t.sk_contract_ticket
            AND t.sk_contract_ticket != -1
            AND t.ts_ticket_started BETWEEN te.ts_offboarding_start AND (te.ts_termination_finished + INTERVAL 15 DAYS)
        LATERAL VIEW explode(array(te.sk_tenant, te.sk_owner, t.sk_user)) u AS sk_user_key
    ) exploded
    LEFT JOIN chatbot_by_user cb
        ON TRY_CAST(exploded.sk_user_key AS bigint) = cb.sk_user
        AND exploded.sk_user_key IS NOT NULL
        AND cb.enriched_ts >= exploded.ts_offboarding_start
        AND cb.enriched_ts <= (exploded.ts_termination_finished + INTERVAL 15 DAYS)
),

matched_by_user AS (
    SELECT DISTINCT
        exploded.sk_termination,
        exploded.is_spoc_eligible,
        exploded.is_spoc,
        exploded.sk_contract,
        exploded.status,
        exploded.sk_tenant,
        exploded.sk_owner,
        exploded.ts_offboarding_start,
        exploded.ts_termination_finished,
        exploded.is_mediacao,
        exploded.has_repairs,
        t.sk_ticket,
        t.tipo_ticket,
        t.ts_ticket_started,
        t.last_department,
        t.channel,
        t.replies,
        t.front_or_back,
        t.platform,
        t.team,
        t.unique_row_id,
        (cb.sk_user IS NOT NULL)                               AS is_chatbot
    FROM (
        SELECT
            te.sk_termination,
            te.is_spoc_eligible,
            te.is_spoc,
            te.sk_contract,
            te.status,
            te.sk_tenant,
            te.sk_owner,
            te.ts_offboarding_start,
            te.ts_termination_finished,
            te.is_mediacao,
            te.has_repairs,
            u.sk_user_key
        FROM terminator_enriched AS te
        LATERAL VIEW explode(array(te.sk_tenant, te.sk_owner)) u AS sk_user_key
    ) exploded
    JOIN deduplicated_tickets AS t
        ON exploded.sk_user_key = t.sk_user
        AND t.sk_contract_ticket = -1
        AND t.ts_ticket_started BETWEEN exploded.ts_offboarding_start AND (exploded.ts_termination_finished + INTERVAL 15 DAYS)
    LEFT JOIN chatbot_by_user cb
        ON TRY_CAST(exploded.sk_user_key AS bigint) = cb.sk_user
        AND cb.enriched_ts >= exploded.ts_offboarding_start
        AND cb.enriched_ts <= (exploded.ts_termination_finished + INTERVAL 15 DAYS)
),

matched_without_tickets AS (
    SELECT DISTINCT
        exploded.sk_termination,
        exploded.is_spoc_eligible,
        exploded.is_spoc,
        exploded.sk_contract,
        exploded.status,
        exploded.sk_tenant,
        exploded.sk_owner,
        exploded.ts_offboarding_start,
        exploded.ts_termination_finished,
        exploded.is_mediacao,
        exploded.has_repairs,
        CAST(NULL AS string)                                    AS sk_ticket,
        CAST(NULL AS string)                                    AS tipo_ticket,
        CAST(NULL AS timestamp)                                 AS ts_ticket_started,
        CAST(NULL AS string)                                    AS last_department,
        CAST(NULL AS string)                                    AS channel,
        CAST(0 AS integer)                                      AS replies,
        CAST(NULL AS string)                                    AS front_or_back,
        CAST(NULL AS string)                                    AS platform,
        CAST(NULL AS string)                                    AS team,
        CAST(NULL AS bigint)                                    AS unique_row_id,
        (cb.sk_user IS NOT NULL)                               AS is_chatbot
    FROM (
        SELECT
            te.sk_termination,
            te.is_spoc_eligible,
            te.is_spoc,
            te.sk_contract,
            te.status,
            te.sk_tenant,
            te.sk_owner,
            te.ts_offboarding_start,
            te.ts_termination_finished,
            te.is_mediacao,
            te.has_repairs,
            u.sk_user_key
        FROM terminator_enriched AS te
        LATERAL VIEW explode(array(te.sk_tenant, te.sk_owner)) u AS sk_user_key
    ) exploded
    LEFT JOIN chatbot_by_user cb
        ON TRY_CAST(exploded.sk_user_key AS bigint) = cb.sk_user
        AND exploded.sk_user_key IS NOT NULL
        AND cb.enriched_ts >= exploded.ts_offboarding_start
        AND cb.enriched_ts <= (exploded.ts_termination_finished + INTERVAL 15 DAYS)
    WHERE exploded.sk_termination NOT IN (
        SELECT sk_termination FROM matched_by_contract
        UNION
        SELECT sk_termination FROM matched_by_user
    )
),

terminator_with_tickets AS (
    SELECT sk_termination, is_spoc_eligible, is_spoc, sk_contract, status, sk_tenant, sk_owner, ts_offboarding_start, ts_termination_finished, is_mediacao, has_repairs, sk_ticket, tipo_ticket, ts_ticket_started, last_department, channel, replies, front_or_back, platform, team, unique_row_id, is_chatbot
    FROM matched_by_contract

    UNION ALL

    SELECT sk_termination, is_spoc_eligible, is_spoc, sk_contract, status, sk_tenant, sk_owner, ts_offboarding_start, ts_termination_finished, is_mediacao, has_repairs, sk_ticket, tipo_ticket, ts_ticket_started, last_department, channel, replies, front_or_back, platform, team, unique_row_id, is_chatbot
    FROM matched_by_user

    UNION ALL

    SELECT sk_termination, is_spoc_eligible, is_spoc, sk_contract, status, sk_tenant, sk_owner, ts_offboarding_start, ts_termination_finished, is_mediacao, has_repairs, sk_ticket, tipo_ticket, ts_ticket_started, last_department, channel, replies, front_or_back, platform, team, unique_row_id, is_chatbot
    FROM matched_without_tickets
),

encarteiramento_inteligente_model AS (
    SELECT
        TRY_CAST(get_json_object(inputs, '$.contract_id') AS bigint) AS contract_id,
        TRY_CAST(get_json_object(inputs, '$.request_id') AS bigint)  AS request_id,
        get_json_object(outputs, '$.prediction')                      AS model_prediction,
        service_version
    FROM datalake_emlio_clean.emlio_logs
    WHERE id_service = 'users-and-journeys-ml-service'
        AND year >= 2026
),

filtered AS (
    SELECT
        t.sk_termination,
        t.is_spoc_eligible,
        t.is_spoc,
        t.sk_contract,
        t.status,
        t.sk_tenant,
        t.sk_owner,
        t.ts_offboarding_start,
        t.ts_termination_finished,
        t.is_mediacao,
        t.has_repairs,
        t.sk_ticket,
        t.tipo_ticket,
        t.ts_ticket_started,
        t.last_department,
        t.channel,
        t.replies,
        t.front_or_back,
        t.platform,
        t.team,
        t.unique_row_id,
        t.is_chatbot
    FROM terminator_with_tickets t
    WHERE t.ts_termination_finished IS NOT NULL
        AND status = 'Finalizado'
),

calculated_metrics AS (
    SELECT
        sk_contract,
        sk_termination,
        ts_termination_finished,
        ts_offboarding_start,
        is_spoc_eligible,
        is_spoc,
        status,
        sk_tenant,
        sk_owner,
        is_mediacao,
        has_repairs,
        sk_ticket,
        ticket_theme,
        ticket_last_department,
        channel,
        replies,
        front_or_back,
        team,
        is_chatbot,
        periodo_migracao,
        count_contact,
        count_touch
    FROM (
        SELECT
            fn.sk_contract,
            fn.sk_termination,
            CAST(fn.ts_termination_finished AS DATE)              AS ts_termination_finished,
            CAST(fn.ts_offboarding_start AS DATE)                 AS ts_offboarding_start,
            fn.is_spoc_eligible,
            fn.is_spoc,
            fn.status,
            fn.sk_tenant,
            fn.sk_owner,
            fn.is_mediacao,
            fn.has_repairs,

            fn.sk_ticket,
            fn.tipo_ticket                                         AS ticket_theme,
            fn.ts_ticket_started,
            fn.last_department                                     AS ticket_last_department,
            fn.channel,
            fn.replies,
            fn.front_or_back,
            fn.platform,
            fn.team,
            fn.is_chatbot,

            CASE
                WHEN CAST(fn.ts_offboarding_start AS DATE) < DATE'2026-07-01' THEN 'pre_migracao'
                ELSE 'pos_migracao'
            END                                                     AS periodo_migracao,

            CASE
                WHEN fn.sk_ticket IS NOT NULL THEN 1
                ELSE 0
            END                                                     AS count_contact,

            CASE
                WHEN LOWER(COALESCE(fn.channel, '')) LIKE '%email%' AND fn.replies > 0 THEN fn.replies
                WHEN LOWER(COALESCE(fn.channel, '')) LIKE '%email%' AND fn.replies <= 0 THEN 0
                WHEN fn.sk_ticket IS NOT NULL THEN 1
                ELSE 0
            END                                                     AS count_touch,

            ROW_NUMBER() OVER (
                PARTITION BY
                    fn.sk_termination,
                    COALESCE(CAST(fn.unique_row_id AS string), 'no_ticket')
                ORDER BY fn.is_chatbot DESC
            )                                                       AS rn
        FROM filtered fn
    ) sub
    WHERE rn = 1
),

results AS (
    SELECT
        cm.sk_contract,
        cm.sk_termination,
        CAST(MAX(cm.ts_termination_finished) AS DATE)              AS ts_termination_finished,
        CAST(MAX(cm.ts_offboarding_start) AS DATE)                 AS ts_offboarding_start,
        MAX(cm.periodo_migracao)                                    AS periodo_migracao,
        MAX(cm.is_spoc_eligible)                                    AS is_spoc_eligible,
        MAX(cm.is_spoc)                                             AS is_spoc,
        MAX(cm.status)                                              AS status,
        MAX(cm.sk_tenant)                                           AS sk_tenant,
        MAX(cm.sk_owner)                                            AS sk_owner,
        MAX(cm.is_mediacao)                                         AS is_mediacao,
        MAX(cm.has_repairs)                                         AS has_repairs,

        COLLECT_SET(cm.ticket_theme)                                AS tickets_theme,
        COLLECT_SET(cm.ticket_last_department)                      AS tickets_last_department,
        COLLECT_SET(cm.channel)                                     AS tickets_channel,
        COLLECT_SET(cm.team)                                        AS tickets_team,

        COALESCE(SIZE(COLLECT_SET(cm.sk_ticket)), 0)                AS qtd_tickets,
        COALESCE(SUM(cm.replies), 0)                                AS total_replies,

        COALESCE(SUM(cm.count_contact), 0)
            + MAX(CASE WHEN cm.is_mediacao = true THEN 1 ELSE 0 END)
            + MAX(CASE WHEN cm.is_spoc = true THEN 1 ELSE 0 END)     AS count_contact,
        COALESCE(SUM(cm.count_touch), 0)
            + MAX(CASE WHEN cm.is_mediacao = true THEN 1 ELSE 0 END)
            + MAX(CASE WHEN cm.is_spoc = true THEN 1 ELSE 0 END)     AS count_touch,

        COALESCE(SUM(CASE WHEN cm.front_or_back = 'Front' THEN cm.count_contact ELSE 0 END), 0) AS count_contact_front,
        COALESCE(SUM(CASE WHEN cm.front_or_back = 'Back' THEN cm.count_contact ELSE 0 END), 0)
            + MAX(CASE WHEN cm.is_mediacao = true THEN 1 ELSE 0 END)
            + MAX(CASE WHEN cm.is_spoc = true THEN 1 ELSE 0 END)     AS count_contact_back,

        COALESCE(SUM(CASE WHEN cm.front_or_back = 'Front' THEN cm.count_touch ELSE 0 END), 0)   AS count_touch_front,
        COALESCE(SUM(CASE WHEN cm.front_or_back = 'Back' THEN cm.count_touch ELSE 0 END), 0)
            + MAX(CASE WHEN cm.is_mediacao = true THEN 1 ELSE 0 END)
            + MAX(CASE WHEN cm.is_spoc = true THEN 1 ELSE 0 END)     AS count_touch_back,

        COALESCE(SUM(CASE WHEN cm.front_or_back = 'Legacy' THEN cm.count_contact ELSE 0 END), 0) AS count_contact_legacy,

        MAX(CASE WHEN ((cm.sk_ticket IS NOT NULL) OR (cm.is_mediacao = true) OR (cm.is_spoc = true)) THEN true ELSE false END) AS has_ticket,
        MAX(CASE WHEN (((cm.sk_ticket IS NOT NULL) OR (cm.ticket_last_department IS NOT NULL) OR (cm.is_mediacao = true)) AND cm.is_spoc = false) THEN true ELSE false END) AS human_support_no_spoc,
        MAX(CASE WHEN cm.is_chatbot = true THEN true ELSE false END) AS is_chatbot,

        MAX(CASE WHEN osr.request_id IS NOT NULL THEN true ELSE false END) AS is_encarteiramento_inteligente_model,
        MAX(osr.service_version)                                    AS model_version,
        MAX(osr.model_prediction)                                   AS model_prediction

    FROM calculated_metrics cm
    LEFT JOIN encarteiramento_inteligente_model osr
        ON osr.request_id = cm.sk_termination
    GROUP BY
        cm.sk_contract,
        cm.sk_termination
)

SELECT
    sk_contract,
    sk_termination,
    ts_termination_finished,
    ts_offboarding_start,
    periodo_migracao,
    is_spoc_eligible,
    is_spoc,
    status,
    sk_tenant,
    sk_owner,
    is_mediacao,
    has_repairs,
    tickets_theme,
    tickets_last_department,
    tickets_channel,
    tickets_team,
    qtd_tickets,
    total_replies,
    count_contact,
    count_touch,
    count_contact_front,
    count_contact_back,
    count_touch_front,
    count_touch_back,
    count_contact_legacy,
    has_ticket,
    human_support_no_spoc,
    is_chatbot,
    is_encarteiramento_inteligente_model,
    model_version,
    model_prediction
FROM results
WHERE ts_termination_finished > DATE'2026-08-01'
