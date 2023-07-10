WITH repairs_per_request AS (
    SELECT
        id_request,
        COUNT(id_request) AS number_repairs_needed
    FROM
        datalake_repairs.repair_request_item
    WHERE
        CAST(ts_created AS DATE) >= DATE('2022-01-01')
    GROUP BY 1
),
repair_custom_fields AS (
    SELECT
        rt.id_ticket,
        COALESCE(rt.id_contract, rcf.id_contract) AS id_contract,
        GET_JSON_OBJECT(rt.service_provider,'$.type') AS service_provider,
        rt.tags,
        CASE
            WHEN rcf.client_type = 'proprietário_de_aluguel' THEN 'proprietário'
            ELSE rcf.client_type
        END AS client_type,
        rcf.custom_fields,
        CASE
            WHEN ARRAY_CONTAINS(rt.tags, "iq_autosservico_negociacao_chat")
                OR ARRAY_CONTAINS(rt.tags, "pp_autosservico_negociacao_chat")
                THEN 'chat_ativo'
        END AS chat_negociation_tag,
        CASE
            WHEN
                COALESCE(rcf.new_criticality, rcf.criticality, rcf.service_rating_tags) LIKE "%comum%"
                OR rt.group_name = "Reparos Comuns [Back]"
                OR (
                    ARRAY_CONTAINS(rt.tags, "triagem_automatica_comum")
                    AND ARRAY_CONTAINS(rt.tags, "resolve_iq_pp_autosservico_prestadorpp")
                )
                THEN "Comum"
            WHEN
                COALESCE(rcf.new_criticality, rcf.criticality, rcf.service_rating_tags) LIKE "%urgente%"
                OR rt.group_name = "Reparos Urgentes [Back]"
                OR (
                    ARRAY_CONTAINS(rt.tags, "triagem_automatica_urgente")
                    AND ARRAY_CONTAINS(rt.tags, "resolve_iq_pp_autosservico_prestadorpp")
                )
                THEN "Urgente"
            WHEN COALESCE(rcf.new_criticality, rcf.criticality, rcf.service_rating_tags) LIKE "%emergencial%"
                OR rt.group_name = "Reparos N2 - Emergenciais [QA]"
                OR (
                    ARRAY_CONTAINS(rt.tags, "triagem_automatica_emergencial")
                    AND ARRAY_CONTAINS(rt.tags, "resolve_iq_pp_autosservico_prestadorpp")
                )
                THEN "Emergencial"
            WHEN COALESCE(rcf.new_criticality, rcf.criticality, rcf.service_rating_tags) IS NOT NULL
                OR rt.group_name = 'FullService [BACK]'
                THEN "Outros"
            ELSE "Sem Definição"
        END AS criticality,
        CASE
            WHEN SIZE(ARRAY_INTERSECT(rt.tags, ARRAY(
                    "comum_iniciar_compulsoria",
                    "comum_-_iniciar_compulsória_",
                    "mediação_início_compulsória",
                    "compulsoria_orcamento_aprovado",
                    "execução_compulsória",
                    "urgente_-_iniciar_compulsória"
                ))) <> 0 THEN "Compulsória"
            WHEN ARRAY_CONTAINS(rt.tags, "mediação_novo_fluxo")
                AND (
                    COALESCE(rcf.new_criticality, rcf.criticality, rcf.service_rating_tags) LIKE "%urgente%"
                    OR rt.group_name = "Reparos Urgentes [Back]"
                    OR (
                        ARRAY_CONTAINS(rt.tags, "triagem_automatica_urgente")
                        AND ARRAY_CONTAINS(rt.tags, "resolve_iq_pp_autosservico_prestadorpp")
                    )
                ) THEN "Compulsória"
            WHEN GET_JSON_OBJECT(rt.service_provider,'$.type') = "TENANT_PROVIDER" THEN "PS IQ'"
            WHEN ARRAY_CONTAINS(rt.tags, "iq_pp_autosserviço_prestadorpp") THEN 'PS Próprio'
            WHEN ARRAY_CONTAINS(rt.tags, "iq_autosservico_negociacao_chat") THEN 'Chat'
            WHEN ARRAY_CONTAINS(rt.tags, "iq_pp_autosserviço_contestou")
                OR ARRAY_CONTAINS(rt.tags, "pp_autosserviço_contestou")
                THEN 'Contestação'
            ELSE 'Normal'
        END AS repair_flow,
        CASE
            WHEN DATE(rt.ts_created_local) < DATE('2023-02-01') THEN 0
            WHEN ARRAY_CONTAINS(rt.tags, "triagem_automatica_comum")
                AND DATE(rt.ts_created_local) < DATE('2023-02-09') THEN 72
            WHEN ARRAY_CONTAINS(rt.tags, "triagem_automatica_comum")
                AND DATE(rt.ts_created_local) >= DATE('2023-02-09') THEN 48
            WHEN ARRAY_CONTAINS(rt.tags, "triagem_automatica_urgente")
                AND DATE(rt.ts_created_local) >= DATE('2023-02-01') THEN 24
            ELSE 0
        END AS ldt_pending,
        DATEDIFF(rt.ts_solved, rt.ts_created) AS frt,
        DATEDIFF(rcf.ts_first_reply, rt.ts_created) AS days_to_first_reply,
        CASE
            WHEN rt.ts_created >= DATE("2023-04-13")
                AND (
                    ARRAY_CONTAINS(rt.tags, "iq_autosservico_negociacao_chat")
                    OR ARRAY_CONTAINS(rt.tags, "pp_autosservico_negociacao_chat")
                    OR GET_JSON_OBJECT(rt.service_provider,'$.type') = 'OWNER_PROVIDER'
                )
                THEN TRUE
            ELSE FALSE
        END AS has_fup,
        CASE
            WHEN rt.reopens > 0 THEN TRUE
            ELSE FALSE
        END AS has_reopen,
        CASE
            WHEN ARRAY_CONTAINS(rt.tags, "iq_pp_autosserviço_prestadorpp")
                OR ARRAY_CONTAINS(rt.tags, "pp_autosserviço_prestadorpp")
                THEN TRUE
            ELSE FALSE
        END AS is_open_auto_service,
        CASE
            WHEN rt.ts_created IS NOT NULL AND rt.ts_solved IS NULL THEN TRUE
            ELSE FALSE
        END AS is_ongoing,
        CASE
            WHEN ARRAY_CONTAINS(rt.tags, "resolve_iq_pp_autosservico_prestadorpp")
                OR ARRAY_CONTAINS(rt.tags, "iq_pp_autosserviço_prestadorpp")
                OR ARRAY_CONTAINS(rt.tags, "pp_autosserviço_prestadorpp")
                OR ARRAY_CONTAINS(rt.tags, "iq_fup_iq_acordo")
                OR ARRAY_CONTAINS(rt.tags, "pp_fup_iq_acordo")
                THEN TRUE
            ELSE FALSE
        END AS is_resolved_by_auto_service,
        CASE
            WHEN ARRAY_CONTAINS(rt.tags, "closed_by_merge") THEN TRUE
            ELSE FALSE
        END AS is_closed_by_merge,
        rcf.ts_first_reply,
        rcf.ts_first_manual_fup_performed,
        rcf.ts_provider_definition,
        rt.ts_solved_local,
        rt.ts_created_local,
        rcf.ts_updated
    FROM
        datalake_repairs.repair_tickets AS rt
    JOIN
        datalake_repairs.repair_custom_fields AS rcf
            ON rcf.id_ticket = rt.id_ticket
            AND rcf.ts_updated = rt.ts_updated
    WHERE
        rt.year = {year}
        AND rt.month = {month}
        AND rt.day = {day}
),
repair_metrics AS (
    SELECT
        rcf.id_ticket,
        CASE
            WHEN rcf.ts_solved_local IS NULL AND ww.dt_end_8 <= DATE('{year}-{month}-{day}') THEN TRUE
            ELSE FALSE
        END AS is_oor,
        CASE
            WHEN ww.dt_end_1 < (DATE('{year}-{month}-{day}') + INTERVAL -1 DAY)
                AND rcf.ts_first_reply IS NULL
                AND rcf.ts_solved_local IS NULL
                THEN TRUE
            ELSE FALSE
        END AS is_first_reply_backlog,
        CASE
            WHEN rcf.ts_first_reply > ww.dt_end_1
                OR (
                    rcf.ts_first_reply IS NULL
                    AND ww.dt_end_1 < (DATE('{year}-{month}-{day}') + INTERVAL -1 DAY)
                )
                THEN TRUE
            ELSE FALSE
        END AS is_first_reply_generated_backlog,
        CASE
            WHEN rcf.ts_first_manual_fup_performed IS NULL
                AND ww.dt_end_2 < (DATE('{year}-{month}-{day}') + INTERVAL -1 DAY)
                AND rcf.ts_solved_local IS NULL
                THEN TRUE
            ELSE FALSE
        END AS is_backlog_fup,
        CASE
            WHEN rcf.ts_provider_definition IS NULL
                AND ww.dt_end_3 < (DATE('{year}-{month}-{day}') + INTERVAL -1 DAY)
                AND rcf.ts_solved_local IS NULL
                THEN TRUE
            ELSE FALSE
        END AS is_backlog_definition,
        CASE
            WHEN
                (
                    ww.dt_end_2 < (DATE('{year}-{month}-{day}') + INTERVAL -1 DAY)
                    AND rcf.ts_solved_local IS NULL
                ) OR (
                    DATE(rcf.ts_first_manual_fup_performed) > ww.dt_end_2
                    AND rcf.ts_solved_local >= rcf.ts_first_manual_fup_performed
                ) THEN TRUE
            ELSE FALSE
        END AS is_backlog_fup_generated,
        CASE
            WHEN
                (
                    ww.dt_end_3 < (DATE('{year}-{month}-{day}') + INTERVAL -1 DAY)
                    AND rcf.ts_solved_local IS NULL
                ) OR (
                    DATE(rcf.ts_provider_definition) > ww.dt_end_3
                    AND rcf.ts_solved_local >= rcf.ts_provider_definition
                ) THEN TRUE
            ELSE FALSE
        END AS is_backlog_definition_generated,
        CASE
            WHEN rcf.service_provider = 'TENANT_PROVIDER' AND rcf.criticality IN ('Comum', 'Urgente', 'Emergencial') THEN ww.dt_end_10
            WHEN rcf.repair_flow = 'Compulsória' AND rcf.criticality = 'Comum' THEN ww.dt_end_13
            WHEN rcf.repair_flow = 'Compulsória' AND rcf.criticality IN ('Urgente', 'Emergencial') THEN ww.dt_end_9
            WHEN rcf.repair_flow = 'Contestação' AND rcf.criticality = 'Comum' THEN ww.dt_end_9
            WHEN rcf.repair_flow = 'Contestação' AND rcf.criticality IN ('Urgente', 'Emergencial') THEN ww.dt_end_6
            WHEN rcf.repair_flow NOT IN ('Compulsória', 'Contestação') AND rcf.criticality = 'Comum' THEN ww.dt_end_8
            WHEN rcf.repair_flow NOT IN ('Compulsória', 'Contestação') AND rcf.criticality = 'Urgente' THEN ww.dt_end_5
            WHEN rcf.repair_flow NOT IN ('Compulsória', 'Contestação') AND rcf.criticality = 'Emergencial' THEN ww.dt_end_3
            ELSE ww.dt_end_3
        END AS dt_deadline,
        CASE
            WHEN rcf.has_fup IS TRUE THEN ww.dt_end_5
            WHEN rcf.ts_created_local >= DATE('2023-05-22')
                AND (
                    ARRAY_CONTAINS(rcf.tags, "iq_pp_escolheu_prestador_iq_aprovar_orcamento")
                    OR ARRAY_CONTAINS(rcf.tags, "pp_escolheu_prestador_iq_aprovar_orcamento")
                    OR ARRAY_CONTAINS(rcf.tags, "iq_pp_escolheu_prestador_iq_aprovar_menor_valor")
                ) THEN ww.dt_end_3
            WHEN rcf.criticality = "Comum" AND rcf.has_fup IS FALSE
                AND (
                    rcf.ts_created_local >= DATE('2023-05-22')
                    OR rcf.ts_first_reply >= DATE('2023-05-22')
                ) THEN ww.dt_end_8
            ELSE ww.dt_end_1
        END AS dt_first_replay_deadline,
        DATEADD(DAY, 8 - DAYOFWEEK(DATEADD(HOUR, rcf.ldt_pending, rcf.ts_created_local)), DATEADD(HOUR, rcf.ldt_pending, rcf.ts_created_local)) AS dt_oor_first_replay,
        ww.dt_end_8 AS dt_expected_closing,
        ww.dt_end_2 AS dt_limit_fup,
        ww.dt_end_3 AS dt_limit_definition,
        rcf.ts_updated
    FROM
        repair_custom_fields AS rcf
    LEFT JOIN
        datalake_date.workday_window AS ww
            ON ww.dt_ref = DATE(rcf.ts_created_local)
                AND ww.id_city = 39
),
sla_target AS (
    WITH sla_metric_target AS (
        SELECT
            st.squad,
            st.target,
            CASE
                WHEN LOWER(st.squad) LIKE "%compulsória%" THEN 'Compulsória'
                WHEN LOWER(st.squad) LIKE "%contestação%" THEN 'Contestação'
                WHEN st.squad = "Reparos Ongoing First Reply" THEN 'Outros'
                ELSE 'Normal'
            END AS repair_flow,
            CASE
                WHEN LOWER(st.squad) LIKE "%comum%" THEN 'Comum'
                WHEN LOWER(st.squad) LIKE "%emergencial%" THEN 'Emergencial'
                WHEN LOWER(st.squad) LIKE "%urgente%" THEN 'Urgente'
                WHEN st.squad = "Reparos Ongoing First Reply" THEN 'Outros'
                ELSE "Sem Definição"
            END AS criticality,
            CASE
                WHEN LOWER(st.squad) LIKE "%com fup%"
                OR st.squad = "Reparos Ongoing FUP" THEN TRUE
                ELSE FALSE
            END AS has_fup,
            array_remove(ARRAY(st.tag_1, st.tag_2, st.tag_3, st.tag_4, st.tag_5, st.tag_6, st.tag_7, st.tag_8, st.tag_9), "") AS tags,
            st.dt_started,
            st.dt_finished
        FROM
            datalake_gsheets_clean.repair_ongoing_sla_target AS st
        WHERE
            st.granularity = 'week'
            AND st.metric_name = 'LDT'
    )
    SELECT
        t.id_ticket,
        MAX(sla_ticket.target) FILTER(WHERE sla_ticket.target IS NOT NULL) AS sla_ticket_target,
        MAX(sla_first_reply.target) FILTER(WHERE sla_first_reply.target IS NOT NULL) AS sla_first_reply_target,
        MAX(sla_fup.target) FILTER(WHERE sla_fup.target IS NOT NULL) AS sla_fup_target,
        MAX(sla_definition.target) FILTER(WHERE sla_definition.target IS NOT NULL) AS sla_definition_target,
        t.ts_updated
    FROM
        repair_custom_fields AS t
    LEFT JOIN
        sla_metric_target AS sla_ticket
            ON t.ts_created_local BETWEEN sla_ticket.dt_started AND sla_ticket.dt_finished
            AND t.repair_flow = sla_ticket.repair_flow
            AND t.criticality = sla_ticket.criticality
            AND LOWER(sla_ticket.squad) LIKE "%ticket%"
    LEFT JOIN
        sla_metric_target AS sla_first_reply
            ON t.ts_created_local BETWEEN sla_first_reply.dt_started AND sla_first_reply.dt_finished
            AND (
                SIZE(ARRAY_INTERSECT(sla_first_reply.tags, t.tags)) <> 0
                OR SIZE(sla_first_reply.tags) = 0
            )
            AND (
                sla_first_reply.criticality = t.criticality
                OR (
                    sla_first_reply.criticality = 'Outros'
                    AND t.criticality <> 'Comum'
                )
            )
            AND sla_first_reply.has_fup = t.has_fup
            AND LOWER(sla_first_reply.squad) LIKE "%first reply%"
    LEFT JOIN
        sla_metric_target AS sla_fup
            ON t.ts_created_local BETWEEN sla_fup.dt_started AND sla_fup.dt_finished
            AND sla_fup.squad = "Reparos Ongoing FUP"
    LEFT JOIN
        sla_metric_target AS sla_definition
            ON t.ts_created_local BETWEEN sla_definition.dt_started AND sla_definition.dt_finished
            AND sla_definition.squad = "Reparos Ongoing Definição"
    GROUP BY 1, 6
)
SELECT
    rt.id_ticket,
    rt.id_repair_request,
    rcf.id_contract,
    rt.id_assignee,
    rt.id_group,
    CASE
        WHEN u.email IS NULL
            AND rm.dt_deadline < (DATE('{year}-{month}-{day}') + INTERVAL -1 DAY)
            THEN 'Sem Atribuição'
        ELSE u.email
    END AS assignee_email,
    rcf.client_type,
    rt.status,
    rt.replies,
    rt.tags,
    rt.channel,
    rt.reopens,
    rt.group_name,
    rt.ticket_via,
    rcf.custom_fields,
    CASE
        WHEN rcf.id_contract IS NULL THEN NULL
        WHEN DATEDIFF(c.dt_entered, rt.ts_created_local) <= 40 THEN 'Onboarding'
        ELSE 'Ongoing'
    END AS journey_step,
    rcf.chat_negociation_tag,
    rcf.service_provider,
    rcf.criticality,
    rcf.repair_flow,
    rpr.number_repairs_needed,
    st.sla_ticket_target,
    st.sla_first_reply_target,
    st.sla_fup_target,
    st.sla_definition_target,
    rcf.frt,
    rcf.days_to_first_reply,
    rcf.ldt_pending,
    DATEDIFF(rcf.ts_first_manual_fup_performed, rcf.ts_first_reply) AS ldt_fup,
    DATEDIFF(rcf.ts_provider_definition, rcf.ts_first_manual_fup_performed) AS ldt_definition,
    rcf.has_reopen,
    rcf.has_fup,
    rcf.is_open_auto_service,
    rcf.is_resolved_by_auto_service,
    rcf.is_closed_by_merge,
    rcf.is_ongoing,
    rm.is_oor,
    CASE
        WHEN rcf.ts_first_reply > rm.dt_first_replay_deadline
            OR rcf.ts_first_reply IS NULL
            AND rm.dt_deadline < (DATE('{year}-{month}-{day}') + INTERVAL -1 DAY)
            THEN TRUE
        ELSE FALSE
    END AS is_oor_first_reply_day,
    CASE
        WHEN rt.ts_solved_local > rm.dt_first_replay_deadline
            OR rt.ts_solved_local IS NULL
            AND rm.dt_deadline < (DATE('{year}-{month}-{day}') + INTERVAL -1 DAY)
            THEN TRUE
        ELSE FALSE
    END AS is_oor_ticket_backlog_day,
    CASE
        WHEN DATEADD(DAY, 20, rt.ts_created_local) < rt.ts_solved_local
            AND rt.ts_solved_local IS NOT NULL THEN TRUE
        WHEN DATEADD(DAY, 20, rt.ts_created_local) < (DATE('{year}-{month}-{day}') + INTERVAL -1 DAY)
            AND rt.ts_solved_local IS NULL THEN TRUE
        ELSE FALSE
    END AS is_anomaly_20_days,
    CASE
        WHEN DATEADD(DAY, 30, rt.ts_created_local) < rt.ts_solved_local
            AND rt.ts_solved_local IS NOT NULL THEN TRUE
        WHEN DATEADD(DAY, 30, rt.ts_created_local) < (DATE('{year}-{month}-{day}') + INTERVAL -1 DAY)
            AND rt.ts_solved_local IS NULL THEN TRUE
        ELSE FALSE
    END AS is_anomaly_30_days,
    CASE
        WHEN DATE('{year}-{month}-{day}') >= rm.dt_deadline
            AND rt.ts_solved_local IS NULL THEN TRUE
        ELSE FALSE
    END AS is_backlog_ticket,
    CASE
        WHEN rt.ts_solved_local >= rm.dt_deadline
            OR (
                rt.ts_solved_local IS NULL
                AND rm.dt_deadline <= DATE('{year}-{month}-{day}')
            ) THEN TRUE
        else FALSE
    END AS is_backlog_ticket_generated,
    rm.is_backlog_fup,
    rm.is_backlog_definition,
    rm.is_backlog_fup_generated,
    rm.is_backlog_definition_generated,
    rm.is_first_reply_backlog,
    rm.is_first_reply_generated_backlog,
    rm.dt_deadline,
    rm.dt_first_replay_deadline,
    rm.dt_oor_first_replay,
    rm.dt_expected_closing,
    rm.dt_limit_fup,
    rm.dt_limit_definition,
    DATEADD(DAY, 8 - DAYOFWEEK(rm.dt_deadline), rm.dt_deadline) AS dt_oor_ticket_week,
    CASE
        WHEN DATEADD(DAY, 20, rt.ts_created_local) > DATE('{year}-{month}-{day}') THEN NULL
        ELSE DATEADD(DAY, 20, rt.ts_created_local)
    END AS dt_anomaly_20_days,
    CASE
        WHEN DATEADD(DAY, 30, rt.ts_created_local) > DATE('{year}-{month}-{day}') THEN NULL
        ELSE DATEADD(DAY, 30, rt.ts_created_local)
    END AS dt_anomaly_30_days,
    c.dt_entered,
    rcf.ts_first_reply,
    rcf.ts_first_manual_fup_performed,
    rcf.ts_provider_definition,
    rt.ts_solved,
    rt.ts_solved_local,
    rt.ts_created_repair_request,
    rt.ts_created,
    rt.ts_created_local,
    rt.ts_updated,
    rt.ts_updated_local,
    rt.year,
    rt.month,
    rt.day
FROM
    datalake_repairs.repair_tickets AS rt
INNER JOIN
    repair_custom_fields AS rcf
        ON rcf.id_ticket = rt.id_ticket
        AND rcf.ts_updated = rt.ts_updated
INNER JOIN
    repair_metrics AS rm
        ON rm.id_ticket = rt.id_ticket
        AND rm.ts_updated = rt.ts_updated
INNER JOIN
    sla_target AS st
        ON st.id_ticket = rt.id_ticket
        AND st.ts_updated = rt.ts_updated
LEFT JOIN
    datalake_ebdb_contract.contract AS c
        ON c.id = rcf.id_contract
LEFT JOIN
    datalake_zendesk_tickets_clean.users AS u
        ON u.id_user = rt.id_assignee
        AND u.role = "agent"
LEFT JOIN
    repairs_per_request AS rpr
        ON rpr.id_request = rt.id_repair_request
WHERE
    rt.group_name IN ("Reparos [BACK]", "Triagem Reparos [Back]")
    AND (
            rt.ts_created >= DATEADD(WEEK, -25, DATE("{year}-{month}-{day}"))
            OR rt.ts_solved >= DATE('2023-01-01')
            OR rt.ts_solved IS NULL
    )
    AND rt.channel NOT IN ("call")
    AND rt.status NOT IN ("deleted")
    AND NOT ARRAY_CONTAINS(rt.tags, "caso_ticket_agregador")