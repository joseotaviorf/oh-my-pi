WITH groups AS (
    SELECT DISTINCT
        id_group,
        name
    FROM
        datalake_zendesk_clean.groups
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_group ORDER BY ts_updated DESC) = 1
),
tickets AS (
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
        REGEXP_REPLACE(
            REGEXP_REPLACE(
                custom_fields,
                '^\\\[|\\\{{([^\\\n\\\{{\\\}}\\\[\\\]](?!value":(?!null)))*\\\}}(,|)|\\\]$', ""
            ),
        ',$|\\\{{|\\\}}|"id":|,"value"|"', ""
        ) AS cf_string,
        priority,
        recipient,
        tags,
        status,
        type,
        satisfaction_rating,
        is_public,
        dt_extracted,
        ts_created,
        ts_updated,
        year,
        month,
        day
    FROM
        datalake_zendesk_clean.tickets
    WHERE
        (
            raw_subject != "scrubbed"
            AND via_channel IS NOT NULL
        )
        AND year = {year}
        AND month = {month}
        AND day = {day}
),
exploded_cf AS (
    SELECT
        id_ticket,
        ts_updated,
        EXPLODE(SPLIT(cf_string, ",")) AS cf
    FROM
        tickets
),
splitted_cf AS (
    SELECT
        id_ticket,
        ts_updated,
        SPLIT(cf, ":")[0] AS key,
        SPLIT(cf, ":")[1] AS value
    FROM
        exploded_cf
),
parsed_cf AS (
    SELECT
        cf.id_ticket,
        cf.ts_updated,
        tf.raw_title AS cf_title,
        cf.value AS cf_value
    FROM
        splitted_cf AS cf
    INNER JOIN
        datalake_zendesk_clean.ticket_fields AS tf
            ON tf.id_ticket_field = cf.key
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY cf.id_ticket, cf.ts_updated, tf.title ORDER BY tf.ts_updated DESC) = 1
),
custom_fields_with_title AS (
    SELECT
        id_ticket,
        ts_updated,
        MAP_FROM_ARRAYS(COLLECT_LIST(cf_title), COLLECT_LIST(cf_value)) AS custom_fields
    FROM
        parsed_cf
    GROUP BY 1, 2
),
tickets_with_fields AS (
    SELECT
        t.id_ticket,
        t.id_assignee,
        t.id_requester,
        t.id_submitter,
        t.id_group,
        t.cf_map["6293000658957"] AS id_problem_ticket, -- custom_field 'Ticket Problema ID'
        CASE
            WHEN LENGTH(COALESCE(t.cf_map["31646438"], t.cf_map["9450746299021"])) < 9 -- custom_field 'Código do Imóvel'
            THEN 892700000 + CAST(COALESCE(t.cf_map["31646438"], t.cf_map["9450746299021"]) AS BIGINT)
            ELSE CAST(COALESCE(t.cf_map["31646438"], t.cf_map["9450746299021"]) AS BIGINT)
        END AS id_house,
        t.cf_map["114096515211"] AS id_contract, -- custom_field 'Código do Contrato'
        t.cf_map["360034234371"] AS id_session, -- custom_field 'Session id'
        t.cf_map["360020220412"] AS id_call, -- custom_field '[CALL] Call id'
        t.cf_map["7430852119821"] AS id_job, -- custom_field '[AQ] ID do Job '
        t.cf_map["360040049212"] AS contact_ticket, -- custom_field 'Ticket do contato'
        t.cf_map["360043935931"] AS task_sid_twilio, -- custom_field 'TaskSid Twilio'
        t.cf_map["13771922442381"] AS analyst_email, -- custom_field '[AUTO] Email do Agente'
        MAP_VALUES(MAP_FILTER(t.cf_map, (k, v) -> LENGTH(v) == 20 AND v RLIKE "^[A-Za-z0-9]+$")) AS offer_ids,
        t.cf_map["360047178772"] AS taxonomy_tags, -- custom_field 'Classificação do atendimento (Tags)'
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
        t.cf_map["31542008"] AS request_type, -- custom_field 'Tipo de Solicitação'
        COALESCE(
            t.cf_map["6314265356813"], -- custom_field 'Tipo de Cliente'
            t.cf_map["46785608"], -- custom_field 'Tipo de Cliente'
            REPLACE(
                REPLACE(
                    REPLACE(
                        t.cf_map["360032588792"], -- custom_field '[CC] - Tipo de Cliente'
                        'cc_',''
                    ),
                    'er_', 'er'
                ),
            'serviços', 'serviço'
            )
        ) AS client_type,
        SPLIT(t.cf_map["360047178772"], '__')[0] AS step_tag, -- custom_field 'Classificação do atendimento (Tags)'
        COALESCE(
            SPLIT(t.cf_map["360047178772"], '__')[1], -- custom_field 'Classificação do atendimento (Tags)'
            t.cf_map["360034564591"] -- custom_field 'Cliente Tag'
        ) AS customer_type_tag,
        COALESCE(
            SPLIT(t.cf_map["360047178772"], '__')[2], -- custom_field 'Classificação do atendimento (Tags)'
            t.cf_map["360034565211"], -- custom_field 'Assunto Tag'
            t.cf_map["31542008"], -- custom_field 'Tipo de Solicitação'
            t.cf_map["360032636211"], -- custom_field '[CC] - Assunto do Contato'
            t.cf_map["360039312451"], -- custom_field '[NG] Tipo de solicitação (IGPM/IPCA)'
            t.cf_map["360043077831"], -- custom_field '[PAY] Tipo de Solicitação'
            t.cf_map["360041425471"] -- custom_field 'Tema do DM"'
        ) AS contact_theme_tag,
        COALESCE(
            SPLIT(t.cf_map["360047178772"], '__')[3], -- custom_field 'Classificação do atendimento (Tags)'
            t.cf_map["360034579652"], -- custom_field 'Motivo Tag'
            t.cf_map["360032589092"] -- custom_field '[CC] - Motivo do contato'
        ) AS contact_motivation_tag,
        SPLIT(
            t.cf_map["360047178772"], '__' -- custom_field 'Classificação do atendimento (Tags)'
        )[4] AS contact_theme_detail_tag,
        t.cf_map["360048803431"] AS protection_agreement, -- custom_field 'Acordo da Proteção'
        t.cf_map["1900000936527"] AS repair_class, -- custom_field 'Classificação de Reparo 1'
        t.cf_map["360047338991"] AS repair_type, -- custom_field 'Classificação de Reparo 2'
        t.cf_map["360047339011"] AS repair_detailed, -- custom_field 'Classificação de Reparo 3'
        t.cf_map["10479892278541"] AS new_criticality, -- custom_field 'Nova criticidade'
        t.cf_map["10479805451021"] AS criticality, -- custom_field 'Criticidade'
        t.cf_map["10480210959117"] AS repair_execution_flow, -- custom_field 'Fluxo de execução dos reparos'
        t.cf_map["1900001343127"] AS demand_type, -- custom_field 'Tipo de Demanda'
        t.cf_map["1900001343147"] AS process_type,-- custom_field 'Tipo de processo'
        t.cf_map["360042230051"] AS client_description, -- custom_field 'O cliente é?'
        t.cf_map["1900001609367"] AS repair_reanalysis, -- custom_field 'Reanalise de Reparos'
        t.cf_map["1900001402347"] AS repairs_sent_to_ll, -- custom_field 'Reparos enviados ao PP'
        t.cf_map["360048322332"] AS interaction_ll, -- custom_field 'Interação com PP'
        t.cf_map["1900001402327"] AS budgeting_performed, -- custom_field 'Orçamentação Realizada'
        t.cf_map["14967527222413"] AS intermediation_with_parties, -- custom_field 'Intermediação com as partes'
        t.cf_map["360047764691"] AS agreement_execution,-- custom_field 'Execução de Acordo'
        COALESCE(
            t.cf_map["114102800872"], -- custom_field 'Finalização'
            t.cf_map["360047730172"]  -- custom_field 'Finalização'
        ) AS finishing,
        t.cf_map["360047289651"] AS budget_value,-- custom_field 'Valor da Orçamentação'
        t.cf_map["360047289671"] AS budget_range,-- custom_field 'Faixa da Orçamentação'
        COALESCE(
            t.cf_map["360047937972"], -- custom_field 'Conclusão da Reanalise de Reparos'
            t.cf_map["1900001609467"] -- custom_field 'Conclusão da Reanalise de Reparos'
        ) AS repair_reanalysis_tags,
        COALESCE(
            t.cf_map["15038539737869"], -- custom_field 'Acordo entre as partes'
            t.cf_map["14967627395085"], -- custom_field 'Acordo entre as partes'
            t.cf_map["360047703591"] -- custom_field 'Acordo entre as partes'
        ) AS agreement_between_parties,
        t.cf_map["1900001343227"] AS dt_communicated_tt, -- custom_field '[Data] Comunicação enviada ao IQ'
        t.cf_map["1900001343267"] AS dt_intermediate, -- custom_field '[Data] Intermediação com as partes'
        t.cf_map["360047678412"] AS dt_agreement_executed, -- custom_field '[Data] Execução do acordo'
        COALESCE(
            t.cf_map["6736556276621"], -- custom_field '[Data] Finalização'
            t.cf_map["1900001343287"]  -- custom_field '[Data] Finalização'
        ) AS dt_finished,
        t.cf_map["31541768"] AS dt_return, -- custom_field 'Data para retorno'
        t.cf_map["1900001343187"] AS dt_budgeted, -- custom_field '[Data] Orçamentação realizada '
        t.cf_map["1900001343207"] AS dt_analysis, -- custom_field '[Data] Reparos enviados ao PP'
        t.cf_map["1900001609407"] AS dt_reanalysis, -- custom_field '[Data] Reanalise de Reparos'
        COALESCE(
            t.cf_map["12818602151181"], -- custom_field '[SO] Código do Imóvel'
            t.cf_map["11569326641293"] -- custom_field '[SO] Código do Imóvel '
        ) AS id_house_so,
        t.cf_map["13499154848781"] AS dt_install, -- custom_field '[SO] Data de instalação'
        t.cf_map["11517025433997"] AS listing_type, -- custom_field '[SO] Tipo de anúncio '
        COALESCE(
            t.cf_map["6183069755405"], -- custom_field '[SO] Motivo'
            t.cf_map["6182669420173"], -- custom_field '[SO] Motivo'
            t.cf_map["11517324829197"] -- custom_field '[SO] Motivo '
        ) AS install_reason,
        t.cf_map["11517180556429"] AS install_agent, -- custom_field '[SO] Agente Instalação'
        t.cf_map["11517277980045"] AS has_plaquinha, -- custom_field '[SO] Instalação realizada'
        t.cf_map["7401994966285"] AS id_house_aq, -- custom_field '[AQ] ID do imóvel'
        t.cf_map["7118963058317"] AS user_sender, -- custom_field '[AQ] User_sender'
        t.cf_map["6698471914509"] AS house_classification, -- custom_field '[AQ] Classificação do Imóvel'
        COALESCE(
            t.cf_map["7229025215373"], -- custom_field '[AQ] Motivo da Classificação do Imóvel 1'
            t.cf_map["7229073331213"], -- custom_field '[AQ] Motivo da Classificação do Imóvel 2'
            t.cf_map["7229085538189"], -- custom_field '[AQ] Motivo da Classificação do Imóvel 3'
            t.cf_map["7229047296013"]  -- custom_field '[AQ] Motivo da Classificação do Imóvel 4'
        ) AS house_classification_reason,
        t.cf_map["7119017157901"] AS signboard_location, -- custom_field '[AQ] Tem plaquinha'
        t.cf_map["7647210235917"] AS video_comments, -- custom_field '[AQ] Comentários do Vídeo'
        t.cf_map["14216500749837"] AS dt_first_fup,  -- custom_field '[Data] Data Primeiro FUP Manual Realizado'
        t.cf_map["14216477864717"] AS dt_first_reply, -- custom_field '[Data] Data do first reply'
        cfwt.custom_fields,
        t.is_public,
        t.ts_created,
        t.ts_updated,
        t.year,
        t.month,
        t.day
    FROM
        tickets AS t
    LEFT JOIN
        custom_fields_with_title AS cfwt
            ON cfwt.id_ticket = t.id_ticket
            AND cfwt.ts_updated = t.ts_updated
    WHERE
        t.via_channel != "api"
        OR (
            t.via_channel = "api"
            AND t.tags NOT LIKE "%hsm%"
        )
),
analyst_assignment AS (
  SELECT DISTINCT
      t.id_ticket,
      CASE
          WHEN t.id_assignee = "5124274148" THEN COALESCE(a.id_agent, 5124274148)  -- 5124274148 is bot id
          ELSE t.id_assignee
      END AS id_agent,
      COALESCE(a2.email, a.email) AS email,
      COALESCE(a2.name, a.name) AS name,
      COALESCE(a2.phone, a.phone) AS phone,
      COALESCE(a2.organization, a.organization) AS organization,
      COALESCE(a2.ts_created, a.ts_created) AS ts_created,
      COALESCE(a2.ts_updated, a.ts_updated) AS ts_updated
    FROM
        tickets_with_fields AS t
    LEFT JOIN
        datalake_support_users.analysts AS a
            ON t.analyst_email = a.email
    LEFT JOIN
        datalake_support_users.analysts AS a2
            ON t.id_assignee = a2.id_agent
    WHERE
        t.id_assignee IS NOT NULL
    UNION ALL
    SELECT DISTINCT
        id_ticket,
        id_assignee AS id_agent,
        NULL AS email,
        NULL AS name,
        NULL AS phone,
        NULL AS organization,
        NULL AS ts_created,
        ts_updated
    FROM
        tickets_with_fields
    WHERE
        id_assignee IS NULL
)
SELECT
    t.id_ticket,
    t.id_assignee,
    t.id_requester,
    t.id_submitter,
    t.id_group,
    t.id_problem_ticket,
    t.id_house,
    t.id_contract,
    t.id_session,
    t.id_call,
    t.id_job,
    t.id_house_so,
    t.id_house_aq,
    g.name AS group_name,
    aa.name AS analyst_name,
    aa.email AS analyst_email,
    aa.phone AS analyst_phone,
    aa.organization AS analyst_organization,
    t.custom_fields,
    t.task_sid_twilio,
    t.contact_ticket,
    t.offer_ids,
    t.taxonomy_tags,
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
    t.client_type,
    t.step_tag,
    t.customer_type_tag,
    t.contact_theme_tag,
    t.contact_motivation_tag,
    t.contact_theme_detail_tag,
    t.protection_agreement,
    t.repair_class,
    t.repair_type,
    t.repair_detailed,
    t.new_criticality,
    t.criticality,
    t.repair_execution_flow,
    t.demand_type,
    t.process_type,
    t.client_description,
    t.repair_reanalysis,
    t.repairs_sent_to_ll,
    t.interaction_ll,
    t.budgeting_performed,
    t.intermediation_with_parties,
    t.agreement_execution,
    t.finishing,
    t.budget_value,
    t.budget_range,
    t.repair_reanalysis_tags,
    t.agreement_between_parties,
    t.listing_type,
    t.install_reason,
    t.install_agent,
    t.user_sender,
    t.house_classification,
    t.house_classification_reason,
    t.signboard_location,
    t.video_comments,
    t.has_plaquinha,
    t.is_public,
    t.dt_communicated_tt,
    t.dt_intermediate,
    t.dt_agreement_executed,
    t.dt_finished,
    t.dt_return,
    t.dt_budgeted,
    t.dt_analysis,
    t.dt_reanalysis,
    t.dt_install,
    t.dt_first_fup,
    t.dt_first_reply,
    aa.ts_created AS ts_analyst_started,
    t.ts_created,
    t.ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    tickets_with_fields AS t
LEFT JOIN
    groups AS g
        ON t.id_group = g.id_group
LEFT JOIN
    analyst_assignment AS aa
        ON t.id_ticket = aa.id_ticket
        AND t.ts_updated = aa.ts_updated
