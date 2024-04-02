WITH tickets AS (
    SELECT
        id_ticket,
        id_assignee,
        id_requester,
        id_submitter,
        id_ticket_form,
        id_group,
        subject,
        description,
        via,
        via_channel,
        CASE
            WHEN via_channel IN ('api', 'web')
                AND (
                    tags LIKE '%call_contato_ativo%'
                    OR tags LIKE '%call_contato_receptivo%'
                ) THEN 'call'
            WHEN via_channel IN ('api')
                AND tags LIKE '%form%' THEN 'form_faq'
            WHEN via_channel IN ('web', 'email', 'chat', 'whatsapp') THEN via_channel
            ELSE 'other'
        END AS channel,
        MAP_FILTER(
            STR_TO_MAP(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        custom_fields,
                        '^\\\[|\\\{{([^\\\n\\\{{\\\}}\\\[\\\]](?!value":(?!null)))*\\\}}(,|)|\\\]$', ""
                    ),
                ',$|\\\{{|\\\}}|"id":|,"value"|"', ""
                )
            ),
            (k, v) -> v IS NOT NULL AND v != "" AND v != " "
        ) AS cf_map,
        priority,
        recipient,
        tags,
        status,
        type,
        satisfaction_rating,
        is_public,
        dt_extracted,
        ts_created,
        ts_updated
    FROM
        datalake_zendesk_clean.tickets
    WHERE
        (
            raw_subject != "scrubbed"
            AND via_channel IS NOT NULL
        )
        AND year IN (YEAR(CAST('{year}-{month}-{day}' AS DATE)), YEAR(CAST('{year}-{month}-{day}' AS DATE) + INTERVAL 1 DAY))
        AND month IN (MONTH(CAST('{year}-{month}-{day}' AS DATE)), MONTH(CAST('{year}-{month}-{day}' AS DATE) + INTERVAL 1 DAY))
        AND day IN (DAY(CAST('{year}-{month}-{day}' AS DATE)), DAY(CAST('{year}-{month}-{day}' AS DATE) + INTERVAL 1 DAY))
),
custom_field_values AS (
    SELECT
        id_ticket,
        cf_map["6293000658957"] AS id_problem_ticket, -- custom_field 'Ticket Problema ID'
        CASE
            WHEN LENGTH(COALESCE(cf_map["31646438"], cf_map["9450746299021"])) < 9 -- custom_field 'Código do Imóvel'
            THEN 892700000 + CAST(COALESCE(cf_map["31646438"], cf_map["9450746299021"]) AS BIGINT)
            ELSE CAST(COALESCE(cf_map["31646438"], cf_map["9450746299021"]) AS BIGINT)
        END AS id_house,
        cf_map["114096515211"] AS id_contract, -- custom_field 'Código do Contrato'
        cf_map["360034234371"] AS id_session, -- custom_field 'Session id'
        cf_map["360020220412"] AS id_call, -- custom_field '[CALL] Call id'
        cf_map["7430852119821"] AS id_job, -- custom_field '[AQ] ID do Job '
        cf_map["360040049212"] AS contact_ticket, -- custom_field 'Ticket do contato'
        cf_map["360043935931"] AS task_sid_twilio, -- custom_field 'TaskSid Twilio'
        cf_map["13771922442381"] AS analyst_email, -- custom_field '[AUTO] Email do Agente'
        MAP_VALUES(MAP_FILTER(cf_map, (k, v) -> LENGTH(v) == 20 AND v RLIKE "^[A-Za-z0-9]+$")) AS offer_ids,
        cf_map["360047178772"] AS taxonomy_tags, -- custom_field 'Classificação do atendimento (Tags)'
        COALESCE(
            cf_map["6314265356813"], -- custom_field 'Tipo de Cliente'
            cf_map["46785608"], -- custom_field 'Tipo de Cliente'
            REPLACE(
                REPLACE(
                    REPLACE(
                        cf_map["360032588792"], -- custom_field '[CC] - Tipo de Cliente'
                        'cc_',''
                    ),
                    'er_', 'er'
                ),
            'serviços', 'serviço'
            )
        ) AS client_type,
        SPLIT(cf_map["360047178772"], '__')[0] AS step_tag, -- custom_field 'Classificação do atendimento (Tags)'
        COALESCE(
            SPLIT(cf_map["360047178772"], '__')[1], -- custom_field 'Classificação do atendimento (Tags)'
            cf_map["360034564591"] -- custom_field 'Cliente Tag'
        ) AS customer_type_tag,
        COALESCE(
            SPLIT(cf_map["360047178772"], '__')[2], -- custom_field 'Classificação do atendimento (Tags)'
            cf_map["360034565211"], -- custom_field 'Assunto Tag'
            cf_map["31542008"], -- custom_field 'Tipo de Solicitação'
            cf_map["360032636211"], -- custom_field '[CC] - Assunto do Contato'
            cf_map["360039312451"], -- custom_field '[NG] Tipo de solicitação (IGPM/IPCA)'
            cf_map["360043077831"], -- custom_field '[PAY] Tipo de Solicitação'
            cf_map["360041425471"] -- custom_field 'Tema do DM"'
        ) AS contact_theme_tag,
        COALESCE(
            SPLIT(cf_map["360047178772"], '__')[3], -- custom_field 'Classificação do atendimento (Tags)'
            cf_map["360034579652"], -- custom_field 'Motivo Tag'
            cf_map["360032589092"] -- custom_field '[CC] - Motivo do contato'
        ) AS contact_motivation_tag,
        SPLIT(
            cf_map["360047178772"], '__' -- custom_field 'Classificação do atendimento (Tags)'
        )[4] AS contact_theme_detail_tag,
        cf_map["360048803431"] AS protection_agreement, -- custom_field 'Acordo da Proteção'
        cf_map["1900000936527"] AS repair_class, -- custom_field 'Classificação de Reparo 1'
        cf_map["360047338991"] AS repair_type, -- custom_field 'Classificação de Reparo 2'
        cf_map["360047339011"] AS repair_detailed, -- custom_field 'Classificação de Reparo 3'
        cf_map["10479892278541"] AS new_criticality, -- custom_field 'Nova criticidade'
        cf_map["10479805451021"] AS criticality, -- custom_field 'Criticidade'
        cf_map["10480210959117"] AS repair_execution_flow, -- custom_field 'Fluxo de execução dos reparos'
        cf_map["1900001343127"] AS demand_type, -- custom_field 'Tipo de Demanda'
        cf_map["1900001343147"] AS process_type,-- custom_field 'Tipo de processo'
        cf_map["360042230051"] AS client_description, -- custom_field 'O cliente é?'
        cf_map["1900001609367"] AS repair_reanalysis, -- custom_field 'Reanalise de Reparos'
        cf_map["1900001402347"] AS repairs_sent_to_ll, -- custom_field 'Reparos enviados ao PP'
        cf_map["360048322332"] AS interaction_ll, -- custom_field 'Interação com PP'
        cf_map["1900001402327"] AS budgeting_performed, -- custom_field 'Orçamentação Realizada'
        cf_map["14967527222413"] AS intermediation_with_parties, -- custom_field 'Intermediação com as partes'
        cf_map["360047764691"] AS agreement_execution,-- custom_field 'Execução de Acordo'
        COALESCE(
            cf_map["114102800872"], -- custom_field 'Finalização'
            cf_map["360047730172"]  -- custom_field 'Finalização'
        ) AS finishing,
        cf_map["360047289651"] AS budget_value,-- custom_field 'Valor da Orçamentação'
        cf_map["360047289671"] AS budget_range,-- custom_field 'Faixa da Orçamentação'
        COALESCE(
            cf_map["360047937972"], -- custom_field 'Conclusão da Reanalise de Reparos'
            cf_map["1900001609467"] -- custom_field 'Conclusão da Reanalise de Reparos'
        ) AS repair_reanalysis_tags,
        COALESCE(
            cf_map["15038539737869"], -- custom_field 'Acordo entre as partes'
            cf_map["14967627395085"], -- custom_field 'Acordo entre as partes'
            cf_map["360047703591"] -- custom_field 'Acordo entre as partes'
        ) AS agreement_between_parties,
        cf_map["1900001343227"] AS dt_communicated_tt, -- custom_field '[Data] Comunicação enviada ao IQ'
        cf_map["1900001343267"] AS dt_intermediate, -- custom_field '[Data] Intermediação com as partes'
        cf_map["360047678412"] AS dt_agreement_executed, -- custom_field '[Data] Execução do acordo'
        COALESCE(
            cf_map["6736556276621"], -- custom_field '[Data] Finalização'
            cf_map["1900001343287"]  -- custom_field '[Data] Finalização'
        ) AS dt_finished,
        cf_map["31541768"] AS dt_return, -- custom_field 'Data para retorno'
        cf_map["1900001343187"] AS dt_budgeted, -- custom_field '[Data] Orçamentação realizada '
        cf_map["1900001343207"] AS dt_analysis, -- custom_field '[Data] Reparos enviados ao PP'
        cf_map["1900001609407"] AS dt_reanalysis, -- custom_field '[Data] Reanalise de Reparos'
        COALESCE(
            cf_map["12818602151181"], -- custom_field '[SO] Código do Imóvel'
            cf_map["11569326641293"] -- custom_field '[SO] Código do Imóvel '
        ) AS id_house_so,
        cf_map["13499154848781"] AS dt_install, -- custom_field '[SO] Data de instalação'
        cf_map["11517025433997"] AS listing_type, -- custom_field '[SO] Tipo de anúncio '
        COALESCE(
            cf_map["6183069755405"], -- custom_field '[SO] Motivo'
            cf_map["6182669420173"], -- custom_field '[SO] Motivo'
            cf_map["11517324829197"] -- custom_field '[SO] Motivo '
        ) AS install_reason,
        cf_map["11517180556429"] AS install_agent, -- custom_field '[SO] Agente Instalação'
        cf_map["11517277980045"] AS has_plaquinha, -- custom_field '[SO] Instalação realizada'
        cf_map["7401994966285"] AS id_house_aq, -- custom_field '[AQ] ID do imóvel'
        cf_map["7118963058317"] AS user_sender, -- custom_field '[AQ] User_sender'
        cf_map["6698471914509"] AS house_classification, -- custom_field '[AQ] Classificação do Imóvel'
        COALESCE(
            cf_map["7229025215373"], -- custom_field '[AQ] Motivo da Classificação do Imóvel 1'
            cf_map["7229073331213"], -- custom_field '[AQ] Motivo da Classificação do Imóvel 2'
            cf_map["7229085538189"], -- custom_field '[AQ] Motivo da Classificação do Imóvel 3'
            cf_map["7229047296013"]  -- custom_field '[AQ] Motivo da Classificação do Imóvel 4'
        ) AS house_classification_reason,
        cf_map["7119017157901"] AS signboard_location, -- custom_field '[AQ] Tem plaquinha'
        cf_map["7647210235917"] AS video_comments, -- custom_field '[AQ] Comentários do Vídeo'
        cf_map["14216500749837"] AS dt_first_fup,  -- custom_field '[Data] Data Primeiro FUP Manual Realizado'
        cf_map["14216477864717"] AS dt_first_reply, -- custom_field '[Data] Data do first reply'
        cf_map AS custom_fields,
        ts_updated
    FROM
        tickets
)
SELECT
    t.id_ticket,
    t.id_assignee,
    t.id_group,
    cfv.id_problem_ticket,
    cfv.id_house,
    cfv.id_contract,
    cfv.id_session,
    cfv.id_call,
    cfv.id_job,
    cfv.id_house_so,
    cfv.id_house_aq,
    cfv.custom_fields,
    cfv.task_sid_twilio,
    cfv.contact_ticket,
    cfv.analyst_email,
    cfv.offer_ids,
    cfv.taxonomy_tags,
    t.status,
    t.channel,
    t.subject,
    t.description,
    t.type,
    t.via,
    t.via_channel,
    t.priority,
    t.recipient,
    t.tags,
    t.satisfaction_rating,
    cfv.client_type,
    cfv.step_tag,
    cfv.customer_type_tag,
    cfv.contact_theme_tag,
    cfv.contact_motivation_tag,
    cfv.contact_theme_detail_tag,
    cfv.protection_agreement,
    cfv.repair_class,
    cfv.repair_type,
    cfv.repair_detailed,
    cfv.new_criticality,
    cfv.criticality,
    cfv.repair_execution_flow,
    cfv.demand_type,
    cfv.process_type,
    cfv.client_description,
    cfv.repair_reanalysis,
    cfv.repairs_sent_to_ll,
    cfv.interaction_ll,
    cfv.budgeting_performed,
    cfv.intermediation_with_parties,
    cfv.agreement_execution,
    cfv.finishing,
    cfv.budget_value,
    cfv.budget_range,
    cfv.repair_reanalysis_tags,
    cfv.agreement_between_parties,
    cfv.listing_type,
    cfv.install_reason,
    cfv.install_agent,
    cfv.user_sender,
    cfv.house_classification,
    cfv.house_classification_reason,
    cfv.signboard_location,
    cfv.video_comments,
    cfv.has_plaquinha,
    t.is_public,
    cfv.dt_communicated_tt,
    cfv.dt_intermediate,
    cfv.dt_agreement_executed,
    cfv.dt_finished,
    cfv.dt_return,
    cfv.dt_budgeted,
    cfv.dt_analysis,
    cfv.dt_reanalysis,
    cfv.dt_install,
    cfv.dt_first_fup,
    cfv.dt_first_reply,
    t.dt_extracted,
    t.ts_created,
    t.ts_updated,
    NOW() AS ts_load,
    YEAR(t.dt_extracted) AS year,
    MONTH(t.dt_extracted) AS month,
    DAY(t.dt_extracted) AS day
FROM
    tickets AS t
INNER JOIN
    custom_field_values AS cfv
        ON cfv.id_ticket = t.id_ticket
        AND cfv.ts_updated = t.ts_updated
WHERE
    t.via_channel != "api"
    OR (
        t.via_channel = "api"
        AND t.tags NOT LIKE "%hsm%"
    )
