WITH sla AS (
    SELECT
        sk_ticket ,
        sla_achieved ,
        minutes_full_resolution_time_calendar
    FROM
        (
            -- call 01
            SELECT
                DISTINCT fc.sk_ticket,
                CASE
                    WHEN fcq.seconds_queue_waiting_duration <= 60
                    AND fcq.is_call_abandoned_in_queue = 'False' THEN 1
                    ELSE 0
                END AS sla_achieved ,
                CAST(seconds_total_call_duration AS DECIMAL)/ 60 AS minutes_full_resolution_time_calendar
            FROM
                teravoz.fact_calls fc
            JOIN 
                teravoz.dim_call dc 
                    ON fc.sk_call = dc.sk_call
            LEFT JOIN 
                teravoz.fact_call_queues fcq 
                ON fcq.sk_call = fc.sk_call
            WHERE
                dc.direction = 'inbound'
                AND fc.ts_started_local >= DATE'2018-01-01'
                AND fc.ts_started_local <= DATE'2020-08-20'
            UNION
            -- call 02
            SELECT
                DISTINCT zd.sk_ticket ,
                CASE
                    WHEN fc.seconds_total_wait_time <= 60
                    AND fct.is_answered THEN 1
                    ELSE 0
                END AS sla_achieved ,
                CAST(fc.seconds_duration AS DECIMAL)/ 60 AS minutes_full_resolution_time_calendar
            FROM
                call.fact_calls fc
            INNER JOIN 
                call.dim_call dc 
                    ON fc.sk_call = dc.sk_call
            INNER JOIN 
                call.fact_call_tasks fct 
                    ON fct.sk_call = dc.sk_call
            INNER JOIN 
                call.dim_call_task dct 
                    ON dct.sk_task = fct.sk_task
            INNER JOIN 
                zendesk.fact_tickets zd 
                    ON zd.sk_call = dc.sk_call
            WHERE
                dc.direction = 'inbound'
                AND dc.ts_started > DATE'2020-08-20'
            UNION
            -- chat 01
            SELECT
                DISTINCT fc.sk_ticket ,
                CASE
                    WHEN fc.seconds_first_reply_time / 60 <= 15 THEN 1
                    WHEN fc.seconds_first_reply_time / 60 > 15 THEN 0
                    ELSE NULL
                END AS sla_achieved ,
                CAST(seconds_chat_duration AS DECIMAL)/ 60 AS minutes_full_resolution_time_calendar
            FROM
                zendesk.fact_chats AS fc
            INNER JOIN 
                zendesk.dim_chat AS dc 
                    ON fc.sk_chat = dc.sk_chat
            WHERE
                status <> 'missed'
                AND dc.ts_started_local >= DATE'2018-01-01'
                AND dc.ts_started_local <= DATE'2020-08-20'
            UNION
            -- chat 02
            SELECT
                zd.sk_ticket ,
                CASE
                    WHEN fts.seconds_first_reply / 60 <= 15 THEN 1
                    WHEN fts.seconds_first_reply / 60 > 15 THEN 0
                    ELSE NULL
                END AS sla_achieved ,
                fc.minutes_duration AS minutes_full_resolution_time_calendar
            FROM
                quinto_messenger.fact_chats fc
            JOIN 
                quinto_messenger.dim_chat dc 
                    ON dc.sk_chat = fc.sk_chat
            INNER JOIN 
                quinto_messenger.fact_tasks fts 
                    ON fts.sk_chat = dc.sk_chat
            INNER JOIN 
                quinto_messenger.dim_task dts
                    ON fts.sk_task = dts.sk_task
            INNER JOIN 
                zendesk.fact_tickets zd
                    ON zd.sk_session = fc.sk_session
            WHERE
                dc.ts_created > DATE'2020-08-20'
                AND dc.status <> 'missed'
            UNION
            -- email
            SELECT
                sk_ticket,
                sla_achieved,
                minutes_full_resolution_time_calendar
            FROM
                (
                SELECT
                    ft.sk_ticket,
                    ft.replies,
                    ft.minutes_requester_wait_time_business / 60.0 AS hour_requester_wait_time_business,
                    CASE
                        WHEN ft.replies > 0 THEN hour_requester_wait_time_business / ft.replies
                    END AS rwt_per_reply,
                    CASE
                        WHEN rwt_per_reply <= 6.0 THEN 1
                        ELSE 0
                    END AS sla_achieved,
                    minutes_full_resolution_time_calendar::DECIMAL,
                    minutes_full_resolution_time_business::DECIMAL
                FROM
                    zendesk.fact_tickets AS ft
                JOIN 
                    zendesk.dim_ticket AS dt 
                        ON dt.sk_ticket = ft.sk_ticket
                WHERE
                    dt.channel IN ('email', 'form_faq', 'web', 'other')
                    -- and ft.ts_solved_local is not null
                    -- emails with the tags below are not new demands, therefore, they should not be considered
                    AND dt.tags NOT ILIKE '%resolve_ticket_acompanhamento%'
                    AND dt.tags NOT ILIKE '%fechado_automaticamente_noreply%'
                    AND dt.tags NOT ILIKE '%redirecionado_atendimento_2%'
                    AND dt.tags NOT ILIKE '%closed_by_merge%'
                    AND dt.tags NOT ILIKE '%zapdesk%'
                    AND dt.tags NOT ILIKE '%ticket_via_call%'
                    AND dt.tags NOT ILIKE '%call_contato_receptivo%'
                    AND dt.tags NOT ILIKE '%call_contato_ativo%'
                    AND dt.tags NOT ILIKE '%resolve_ticket_acompanhamento%'
                    AND dt.tags NOT ILIKE '%redirecionado_adm_v1%'
                    -- dt_ref aqui
                    AND ft.ts_solved_local >= DATE'2018-01-01'
                GROUP BY 1,2,3,4,5,6,7 
                )temp
        GROUP BY 1,2,3 
    )
    GROUP BY 1,2,3 
),
last_event_completed_call AS (
    SELECT
        id_call,
        max(id) AS last_event
    FROM
        datalake_bigfone_twilio_prod.call_flex_events
    WHERE
        direction = 'inbound'
        AND event_type = 'task.completed'
    GROUP BY 1 
),
csat_ticket_calls AS (
    SELECT
        DISTINCT
        --       c.id_call, 
        ft.sk_ticket,
        cc.is_solved,
        cc.csat,
        cc.ts_first_call_event,
        --		c.agent_email, 
        c.department_name,
        dept.area_aux
    FROM
        datalake_bigfone_twilio_prod.call_flex_events c
    INNER JOIN 
        last_event_completed_call le 
            ON le.id_call = c.id_call
            AND le.last_event = c.id
    LEFT JOIN 
        datalake_raw.gsheets_department_channel dept 
            ON dept.aux_canal = c.department_name
    INNER JOIN 
        zendesk.fact_tickets ft
            ON ft.sk_call = c.id_call
    INNER JOIN 
        (
            SELECT
                id_call,
                csat_1 AS is_solved,
                CAST(csat_2 AS INTEGER) AS csat,
                min(ts_created_local) AS ts_first_call_event
            FROM
                datalake_bigfone_twilio_prod.call_ivr_events
            GROUP BY 1, 2,3 
        ) cc 
            ON cc.id_call = c.id_call
    WHERE
        cc.ts_first_call_event > DATE'2018-01-01'
        AND cc.ts_first_call_event <= DATE'2020-08-20'
    UNION
    SELECT
        DISTINCT zd.sk_ticket ,
        CASE
            WHEN fc.is_solved IS TRUE THEN 1
            WHEN fc.is_solved IS FALSE THEN 0
            ELSE NULL
        END AS is_solved ,
        fc.csat_rating AS csat ,
        dc.ts_started AS ts_first_call_event ,
        fc.last_queue_name AS department_name ,
        dept.area_aux
    FROM
        call.fact_calls fc
    INNER JOIN 
        call.dim_call dc 
            ON fc.sk_call = dc.sk_call
    JOIN 
        call.fact_call_tasks fct 
            ON fct.sk_call = dc.sk_call
    JOIN 
        call.dim_call_task dct 
            ON dct.sk_task = fct.sk_task
    JOIN 
        zendesk.fact_tickets zd 
            ON zd.sk_call = dc.sk_call
    LEFT JOIN 
        datalake_raw.gsheets_department_channel dept 
            ON dept.aux_canal = fc.last_queue_name
    WHERE
        dc.direction = 'inbound'
        AND dc.ts_started > DATE'2020-08-20' 
),
csat_email_base AS (
    SELECT
        DATE(dt.ts_created_local) AS date_e,
        dt.sk_ticket,
        'email' AS channel,
        dt.score,
        CASE
            WHEN dt.score IN ('good', 'bad') THEN 1
            ELSE 0
        END AS is_answered,
        CASE
            WHEN dt.score IN ('good') THEN 1
            WHEN dt.score IN ('bad') THEN 0
        END AS is_solved,
        CASE
            WHEN dt.score = 'good' THEN 5
            WHEN dt.score = 'bad' THEN 1
            ELSE NULL
        END AS score_num,
        dt.reason,
        dt.comment
    FROM
        zendesk.fact_tickets ft
    JOIN 
        zendesk.dim_ticket dt 
            ON ft.sk_ticket = dt.sk_ticket
    WHERE
        channel IN ('web', 'email', 'form_faq', 'other')
        AND DATE(dt.ts_created_local) >= DATE'2018-01-01'
    GROUP BY 1,2,3,4,5,6,7,8,9 
),
csat_chat_base AS (
    --------------------- chat
    SELECT
        DATEADD('hour',
        -3,
        c.ts_attended)::DATE AS date_c,
        CASE
            WHEN sa.is_solved = TRUE THEN 1
            WHEN sa.is_solved = FALSE THEN 0
            ELSE NULL
        END AS is_solved,
        sa.rating AS csat,
        c.group_name,
        c.id_ticket,
        'chat' AS channel,
        sa.comment
    FROM
        datalake_chat_fup_clean_prod.chats_chat c
    JOIN 
        datalake_chat_fup_clean_prod.surveys_survey ss 
            ON ss.id_chat = c.id
    LEFT JOIN 
        datalake_chat_fup_clean_prod.surveys_answer sa 
            ON ss.id = sa.id_survey
    WHERE
        sa.id IS NOT NULL
        AND DATE(DATEADD('hour',
        -3,
        c.ts_attended)) >= DATE'2018-01-01'
    GROUP BY 1,2,3,4,5,6,7
    ORDER BY 1 DESC,2 
) ,
csat AS (
    SELECT
        ft.sk_ticket,
        ft.sk_contract AS sk_contract_ticket,
        ft.sk_user,
        CASE
            WHEN tk.channel IN ('web', 'email', 'form_faq', 'other') THEN 'email'
            ELSE tk.channel
        END AS channel,
        DATE(tk.ts_created_local) AS ticket_date,
        tk.request_type,
        tk.group_name,
        COALESCE(c.is_solved, cll.is_solved, e.is_solved) AS is_solved,
        COALESCE(c.csat, cll.csat, e.score_num) AS csat
    FROM
        zendesk.fact_tickets ft
    INNER JOIN 
        zendesk.dim_ticket tk 
            ON ft.sk_ticket = tk.sk_ticket
    LEFT JOIN 
        csat_email_base e 
            ON ft.sk_ticket = e.sk_ticket
    LEFT JOIN 
        csat_chat_base c 
            ON ft.sk_ticket = c.id_ticket
    LEFT JOIN 
        csat_ticket_calls cll 
            ON ft.sk_ticket = cll.sk_ticket
    WHERE
        tk.ts_created_local >= DATE'2018-01-01'
    GROUP BY 1,2,3,4,5,6,7,8,9 
) ,
automatically_closed_emails AS (
    SELECT
        DISTINCT tt.sk_ticket
    FROM
        zendesk.fact_ticket_tags tt
    JOIN 
        zendesk.dim_ticket dt 
            ON dt.sk_ticket = tt.sk_ticket
    WHERE
        dt.channel IN ('email', 'form_faq', 'web', 'other')
        AND tt.ticket_tag IN ('resolve_ticket_acompanhamento', 'fechado_automaticamente_noreply', 'redirecionado_atendimento_2', 'closed_by_merge', 'zapdesk', 'ticket_via_call', 'call_contato_receptivo', 'call_contato_ativo', 'resolve_ticket_acompanhamento', 'redirecionado_adm_v1', 'robotserviceaccount02') 
),
ticket_calls AS (
    SELECT
        sk_call,
        sk_ticket
    FROM
        teravoz.fact_calls dc
    WHERE
        sk_ticket IS NOT NULL
    GROUP BY 1,2 
),
last_queue AS (
    SELECT
        sk_call,
        max(ts_queue_joined_local) AS last_queue
    FROM
        teravoz.fact_call_queues fc
    GROUP BY 1 
),
calls_tickets AS (
    SELECT
        tc.sk_ticket,
        CAST(fc.queue_number AS VARCHAR(10)) dept
    FROM
        teravoz.fact_call_queues fc
    INNER JOIN 
        last_queue lq 
            ON lq.sk_call = fc.sk_call
            AND lq.last_queue = fc.ts_queue_joined_local
    INNER JOIN 
        ticket_calls tc 
            ON tc.sk_call = fc.sk_call
    GROUP BY 1,2
    UNION
    SELECT
        ft.sk_ticket,
        fc.last_queue_name AS dept
    FROM
        call.dim_call dc
    INNER JOIN 
        call.fact_calls fc 
            ON fc.sk_call = dc.sk_call
    INNER JOIN 
        zendesk.fact_tickets ft 
            ON ft.sk_call = dc.sk_call 
),
last_task AS (
    SELECT
        id_channel,
        MAX(ts_created) last_timestamp
    FROM
        datalake_quinto_messenger_prod.task t
    GROUP BY 1 
),
chat_tickets AS (
    SELECT
        fc.sk_ticket,
        fc.last_chat_department AS dept
    FROM
        zendesk.fact_chats fc
    JOIN 
        zendesk.dim_chat dc 
        ON dc.sk_chat = fc.sk_chat
    WHERE
        DATE(dc.ts_started_local) <= '2020-08-20'
    GROUP BY 1,2
    UNION
    SELECT
        ft.sk_ticket,
        task_queue_name AS dept
    FROM
        datalake_quinto_messenger_prod.task t
    INNER JOIN 
        last_task lt 
            ON lt.id_channel = t.id_channel
            AND t.ts_created = lt.last_timestamp
    INNER JOIN 
        (
            SELECT
                task_queue_name,
                id_task
            FROM
                datalake_quinto_messenger_prod.task_event
            GROUP BY
                1,
                2 
        ) te 
            ON te.id_task = t.id_task
    INNER JOIN 
        zendesk.fact_tickets ft
            ON ft.sk_session = t.id_conversation
            AND ft.sk_session > 0
    INNER JOIN 
        zendesk.dim_ticket dt
            ON dt.sk_ticket = ft.sk_ticket
    WHERE
        dt.channel IN ('chat')
        AND DATE(dt.ts_created_local) >= '2020-08-21'
    GROUP BY 1,2 
) ,
email_tickets AS (
    SELECT
        dt.sk_ticket,
        dt.group_name AS dept
    FROM
        zendesk.dim_ticket dt
    WHERE
        channel NOT IN ('call', 'chat')
    GROUP BY 1,2 
),
dept_tickets AS (
    SELECT
        *
    FROM
        email_tickets
    UNION
    SELECT
        *
    FROM
        chat_tickets
    UNION
    SELECT
        *
    FROM
        calls_tickets 
) ,
tickets_areas AS (
    SELECT
        dt.sk_ticket,
        gdc.area_aux AS ticket_area,
        dt.dept
    FROM
        dept_tickets dt
    JOIN 
        datalake_raw.gsheets_department_channel AS gdc 
            ON dt.dept = gdc.aux_canal
    WHERE
        area_aux <> '-'
    GROUP BY 1,2,3 
),
tax AS (
    SELECT
        DISTINCT dd.date AS "Data_Hora",
        ft.sk_ticket AS "Ticket_Id",
        dt.channel AS Canal,
        gdc.dept AS Fila,
        ctt.customer_type_tag AS Client,
        ctt.contact_motivation_tag AS Motivation,
        ctt.contact_theme_tag AS Theme,
        gdc.ticket_area AS Area,
        'old' AS taxonomy_version
    FROM
        zendesk.fact_tickets AS ft
    JOIN 
        public.dim_date AS dd 
            ON ft.sk_created_date_local = dd.sk_date
    LEFT JOIN 
        zendesk.fact_ticket_contact_types AS fct 
            ON ft.sk_ticket = fct.sk_ticket
            AND is_contact_type_taxonomy = TRUE
    INNER JOIN 
        datalake_raw.gsheets_contact_types_tags ctt 
            ON ctt.contact_type_tag = fct.contact_type_tag
            AND ctt.is_correspondent_contact_type = 1
    JOIN 
        zendesk.dim_ticket AS dt 
            ON dt.sk_ticket = ft.sk_ticket
    INNER JOIN 
        tickets_areas AS gdc 
            ON dt.sk_ticket = gdc.sk_ticket
    WHERE
        dd.date::DATE < '2020-08-20'
        AND dt.sk_ticket NOT IN (
            SELECT
                *
            FROM
                automatically_closed_emails
        )
        AND fct.contact_type_tag IS NOT NULL
        AND ctt.customer_type_tag <> '-'
        AND ctt.contact_motivation_tag <> '-'
        AND ctt.contact_theme_tag <> '-'
        AND dd.date::DATE >= '2018-01-01'
    UNION
    SELECT
        DISTINCT dd.date AS "Data_Hora",
        ft.sk_ticket AS "Ticket_Id",
        dt.channel AS Canal,
        gdc.dept AS Fila,
        customer_type_tag AS client,
        contact_motivation_tag AS motivation,
        dt.contact_theme_tag AS theme,
        gdc.ticket_area AS Area,
        'new' AS taxonomy_version
    FROM
        zendesk.fact_tickets AS ft
    JOIN 
        public.dim_date AS dd 
            ON ft.sk_created_date_local = dd.sk_date
    JOIN 
        zendesk.dim_ticket AS dt 
            ON dt.sk_ticket = ft.sk_ticket
    INNER JOIN 
        tickets_areas AS gdc 
            ON dt.sk_ticket = gdc.sk_ticket
    WHERE
        dd.date::DATE >= '2020-08-20'
        AND dt.sk_ticket NOT IN (
            SELECT
                *
            FROM
                automatically_closed_emails
        )
        AND customer_type_tag IS NOT NULL
        AND contact_motivation_tag IS NOT NULL
        AND dt.contact_theme_tag IS NOT NULL 
)
SELECT
	DISTINCT ft.sk_ticket,
	ft.sk_contract AS sk_contract_ticket,
	ft.sk_user,
	CASE
		WHEN tk.channel IN ('web', 'email', 'form_faq', 'other') THEN 'email'
		ELSE tk.channel
	END AS channel,
	tk.ts_created_local,
	ft.ts_solved_local,
	ft.ts_closed_local,
	tk.request_type,
	tk.subject,
	tk.group_name,
	ta.ticket_area,
	tax.theme,
    tax.motivation,
    tax.client AS customer,
	CASE
		WHEN tax.theme LIKE '%repair%'
		OR tk.group_name LIKE '%[REP]%' THEN 'repair'
		WHEN tax.theme LIKE '%payment%'
		OR tk.group_name LIKE '%[PAY]%' THEN 'payment'
		WHEN tax.theme LIKE '%visit%'
		OR tk.group_name LIKE '%[VIS]%' THEN 'visit'
		WHEN tax.theme LIKE '%contract%'
		OR tk.group_name LIKE '%[PRO]%' THEN 'contract'
		WHEN tax.theme LIKE '%inspection%'
		OR tk.group_name LIKE '%Vistoria%' THEN 'inspection'
		WHEN tax.theme IS NULL THEN 'null'
		ELSE tax.theme
	END AS theme_tag_agg,
	CASE
        WHEN 
            tk.group_name IN (
                'Processo | Risk Tarefas [FRONT] [SALE] [BACK]','CLosing ForSale/ Financiamento bancário [CLO] [SALE] [BACK]','CX - Compra e Venda [CV]','Closing ForSale/An. de Crédito [CLO] [SALE] [BACK]'
                ,'Closing ForSale/Buyer [CLO][SALE][FRONT]','Closing ForSale/Diligência [CLO][SALE][BACK]','Closing ForSale/Registro Cartório[CLO][SALE][BACK]','Closing ForSale/Seller [CLO][SALE][FRONT]'
                ,'Closing ForSale/Tarefas [CLO] [SALE] [FRONT] [BACK]','Compra e Venda [CV] [BACK]','Consultores - Pré CCV [CV]','Deal Making','Especialistas - Pós CCV [CV]','Relacionamento com corretores - Compra e venda'
            ) 
        THEN 
            'ForSale'
        WHEN 
            tk.group_name IN (
                'Agendamento Fotos - FUP [IS]','Gestão de Consequências [IS]','Inside Sales - ActionLine [IS][OUT]','Inside Sales - Atento [IS][OUT]'
                ,'Inside Sales - Compra e Venda [IS] [CV]','Inside Sales - Prioritário [IS]','Inside Sales [IS]','Listing Quality [FOTOS] [POS] [BACK]'
            ) 
        THEN 
            'IS'
        WHEN 
            tk.group_name IN (
                'Antecipação de Aluguel','B2B [B2B]','BizDev [B2B]','Cobranças [COL] [POS] [BACK]','Dados do PP [Closing_Estela]','Finalizados [COL] [POS] [BACK]'
                ,'Key Account [B2B]','Labs Pré Vendas [LAB]','Labs Pós Vendas [LAB]'
            ) 
        THEN 
            'Não é CX'
        WHEN 
            tk.group_name IN (
                'CX Conta Comigo [POS] [BACK]','Casos Especiais [CE] [POS] [BACK]','Chat PP/IQ','Chat PP/IQ [ONB] [POS] [BACK]','Entrevistas UX','Loyalty [BACK] [POS]'
                ,'Midias Ops [ONB] [POS] [FRONT]','Midias Ops [POS] [BACK]','Ouvidoria [CE] [POS] [BACK]','PROCON [CE] [POS] [BACK]','ReclameAqui [CE] [POS] [BACK]'
                ,'Suporte ao Vistoriador [INS]','Vistoria atendimento interno [INS]'
            ) 
        THEN 
            'Relacionamento'
        WHEN 
            tk.group_name IN (
                'BACK [Propostas]','BACK [Visitas]','CX Anúncio e Visitas Misseds','CX Contratos [PRO] [PRE] [FRONT]','CX Documentação [PRO] [PRE] [FRONT]','CX PROPOSTAS [PRO] [PRE] [FRONT]'
                ,'CX Partners Tarefas [PRE] [BACK]','CX Partners [PRE] [FRONT]','CX SOS Visitas [VIS] [PRE] [FRONT]','CX Suporte ao Parceiro [VIS] [PRE] [FRONT]','CX Visitas Tarefas [PRE][BACK]'
                ,'CX Visitas N1 & N2 [VIS] [PRE] [FRONT] [OUT]','CX Visitas N3 [VIS] [PRE] [FRONT]','Captadores QuintoAndar [B2B] [PRE] [BACK]','Closing - Antecipação [CLO] [PRE] [BACK]'
                ,'Closing - Front End 1 [CLO] [PRE] [BACK]','Closing - Front End 2 [CLO] [PRE] [BACK]','Closing - Front End 3 [CLO] [PRE] [BACK]','Closing - Front End 4 [CLO] [PRE] [BACK]','Closing - Portabilidade [CLO] [PRE] [BACK]'
                ,'Closing - Repescagem [CLO] [PRE] [BACK]','Closing B2B [CLO] [PRE] [BACK]','Closing B2C [CLO] [PRE] [BACK]','Closing FUP (B2B) [CLO] [PRE] [BACK]','Closing FUP (B2C) [CLO] [PRE] [BACK]'
                ,'Closing For Sale/ Pagamentos [CV] [PRE] [BACK]','Closing Front (B2B) [CLO] [PRE] [BACK]','Closing Front (B2C) [CLO] [PRE] [BACK]','Confirmação de Visitas [VIS] [PRE] [FRONT]','Credenciamento Corretores [AGE] [PRE]'
                ,'Crises Field [AGE] [PRE]','E-mail PRÉ [SUP] [PRE] [BACK]','Gestão de Consequências PP [VIS] [PRE] [BACK]','IndicaAí Prestadores [REP]','Irent [VIS] [PRE] [BACK]'
                ,'Lockbox [AGE] [PRE]','Relacionamento Fotógrafos [AGE] [PRE]','TESTE E-mail [PRE] [SUP] [BACK]','Visitas Tarefas [PRE][BACK]'
            ) 
        THEN 
            'Pré-contrato'
        WHEN 
            tk.group_name IN (
                'Aditivos - Ativo [REP] [POS] [FRONT]','Aditivos [REP] [POS] [BACK]','CX Entrada no imóvel [ONB] [POS] [FRONT]','CX Mediações [ONB] [POS] [BACK]','CX ONB/PAY Missed','Entrada no imóvel [ONB] [POS] [BACK]'
                ,'Logística Chaves Onboarding [INS] [POS] [BACK]','Logística Onboarding [INS] [POS] [BACK]','Onboarding Payments','Onboarding Visitas [VIS] [PRE] [FRONT]','[Desativar] CX Entrada no imóvel N3 [POS] [FRONT] [ONB]'
            ) 
        THEN 
            'Onboarding'
        WHEN 
            tk.group_name IN (
                'CX Negociação de aluguel [PAY] [POS] [BACK]','CX ADM - IPTU','CX ADM - Urgente','CX ADM Tier 1 [PAY] [POS] [FRONT]','CX Durante a locação e Reparos [POS] [FRONT] [ATIVO]','CX Durante a locação e reparos [POS] [FRONT]'
                ,'CX Imposto de Renda [PAY] [POS] [FRONT]','CX Negociação IGPM/IPCA [PAY] [POS] [BACK]','CX Pagamentos N1 [PAY] [POS] [FRONT]','CX Pagamentos N3 [PÓS] [FRONT] [PAY]','Lançamento - PP Paga [PAY] [POS] [BACK]'
                ,'Negociação [PAY] [POS] [FRONT]','Pagamentos - Ativo Self Condo [PAY] [POS] [BACK]','Pagamentos - Check [PAY] [POS] [BACK]','Pagamentos - Contato Ativo [PAY] [POS] [BACK]','Pagamentos - Corretores [PAY] [POS] [BACK]'
                ,'Pagamentos - Cross [PAY] [POS] [BACK]','Pagamentos - Faturas [PAY] [POS] [BACK]','Pagamentos - OFF [PAY] [POS] [BACK]','Pagamentos - Pagamentos V9 [PAY] [POS] [BACK]','Pagamentos - Prestadores Parceiros [PAY] [POS] [BACK]'
                ,'Proteção 5A Parceiros [REP] [POS] [BACK]','Proteção QuintoAndar [OFF] [POS] [BACK]','Reparos [REP] [POS] [BACK]','[Desativar] CX IPTU [PAY] [POS] [FRONT]'
            ) 
        THEN 
            'Ongoing'
        WHEN 
            tk.group_name IN (
                'Agendamento Vistoria Saída [OFF] [POS] [BACK]','Agendamento Vistorias [ONB] [POS] [BACK]','CX Rescisão e Vistoria [OFF] [POS] [FRONT]','Emergencial Offboarding Chaves[Pos][BACK]','Evictions [COL][POS][BACK]'
                ,'Log - Credenciamento [INS]','Logística Chaves Offboarding [INS] [POS] [BACK]','Logística Offboarding [INS] [POS] [BACK]','Novo Off - Reparos [POS] [BACK]','Piloto OFF 1 [OFF] [POS] [BACK]'
                ,'Pré-Despejo [COL] [POS] [BACK]','Qualidade de Vistorias [OFF] [POS] [BACK]','Rescisão 1 [OFF] [POS] [BACK]','Rescisão 2 - B2B [OFF] [B2B]','Rescisão 2 [OFF] [POS] [BACK]'
            ) 
        THEN 
            'Offboarding'
        ELSE NULL
    END AS rental_process_step,
	tk.status,
	ft.minutes_first_resolution_time_calendar,
	ft.minutes_first_resolution_time_business,
	sla.sla_achieved,
	sla.minutes_full_resolution_time_calendar,
	CASE
		WHEN csat.is_solved >1 THEN 1
		ELSE csat.is_solved
	END AS is_solved,
	csat.csat
FROM
	zendesk.fact_tickets ft
JOIN 
    zendesk.dim_ticket tk 
        ON ft.sk_ticket = tk.sk_ticket
LEFT JOIN 
    sla 
        ON ft.sk_ticket = sla.sk_ticket
LEFT JOIN 
    tax 
        ON ft.sk_ticket = tax.Ticket_Id
LEFT JOIN 
    csat 
        ON ft.sk_ticket = csat.sk_ticket
LEFT JOIN 
    tickets_areas AS ta 
        ON ta.sk_ticket = ft.sk_ticket
	-- where ft.sk_user<>-1
