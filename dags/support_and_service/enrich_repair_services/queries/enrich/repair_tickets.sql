WITH ongoing_tickets AS (
    SELECT
        tf.id_ticket,
        tfm.id_user,
        tfm.id_zendesk_requester_user,
        tfm.user_name,
        tf.group_name,
        REPLACE(REPLACE(tf.custom_fields, ']', ''),'[', '') AS custom_fields,
        tf.status,
        DATE(tf.ts_created) AS dt_created
    FROM
        datalake_zendesk_ticket_funnels.ticket_funnel tf
    LEFT JOIN
        datalake_zendesk_ticket_funnels.tickets_funnel_metrics tfm
            ON tf.id_ticket = tfm.id_ticket
)
SELECT
    CAST(ot.id_ticket AS BIGINT) AS id_ticket,
    CAST(
        CASE
            WHEN GET_JSON_OBJECT(ot.custom_fields, '$.PAR Tipo de Solicitação') = 'inicial_' THEN ot.id_ticket
            ELSE GET_JSON_OBJECT(ot.custom_fields, '$.PAR Ticket Inicial')
        END AS BIGINT
    ) AS id_ticket_referential,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Ticket de CX') AS BIGINT) AS id_ticket_cx,
    GET_JSON_OBJECT(ot.custom_fields, '$.Código do Contrato') AS id_contract,
    GET_JSON_OBJECT(ot.custom_fields, '$.Código do imóvel') AS id_house,
    GET_JSON_OBJECT(ot.custom_fields, '$.PAR Código do band-aid') AS id_band_aid,
    ot.id_user AS id_provider,
    ot.id_zendesk_requester_user AS id_zendesk_provider,
    ot.user_name AS provider_name,
    ot.group_name,
    ot.status,
    GET_JSON_OBJECT(ot.custom_fields, '$.PAR Status do Ticket') AS ticket_status,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Quantidade de anexos') AS BIGINT) AS number_photos_videos_attached,
    GET_JSON_OBJECT(ot.custom_fields, '$.PAR Prioridade') AS priority,
    GET_JSON_OBJECT(ot.custom_fields, '$.PAR Analista responsável pela orçamentação') AS budget_analyst,
    GET_JSON_OBJECT(ot.custom_fields, '$.PAR Complexidade') AS complexity,
    GET_JSON_OBJECT(ot.custom_fields, '$.PAR Motivo de cancelamento na fase de orçamentação') AS reason_cancellation_budgeting_phase,
    GET_JSON_OBJECT(ot.custom_fields, '$.PAR Motivo do reagendamento da visita de orçamentação') AS reason_rescheduling_budget_visit,
    GET_JSON_OBJECT(ot.custom_fields, '$.PAR Resultado da visita') AS visit_result,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Valor do Orçamento Enviado') AS FLOAT) AS amount_budget_sent,
    GET_JSON_OBJECT(ot.custom_fields, '$.PAR Responsável atraso - Orçamentação') AS responsible_budget_delay,
    GET_JSON_OBJECT(ot.custom_fields, '$.PAR Responsável pelo orçamento aprovado') AS responsible_budget_approved,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Valor do reparo aprovado') AS FLOAT) AS repair_value_approved,
    GET_JSON_OBJECT(ot.custom_fields, '$.PAR Motivo da espera') AS reason_waiting,
    GET_JSON_OBJECT(ot.custom_fields, '$.PAR Analista responsável pela execução') AS responsible_execution,
    GET_JSON_OBJECT(ot.custom_fields, '$.PAR O agendamento foi feito dentro de 5 dias?') AS consultation_duration,
    GET_JSON_OBJECT(ot.custom_fields, '$.PAR Responsável atraso - Agendamento') AS responsible_scheduling_delay,
    GET_JSON_OBJECT(ot.custom_fields, '$.PAR Houve adicional de reparo') AS additional_repair,
    GET_JSON_OBJECT(ot.custom_fields, '$.PAR Tipo de adicional') AS additional_type,
    GET_JSON_OBJECT(ot.custom_fields, '$.PAR Solicitante do adicional') AS additional_requester,
    GET_JSON_OBJECT(ot.custom_fields, '$.PAR A execução aconteceu dentro de 5 dias?') AS execution_period_in_sla,
    GET_JSON_OBJECT(ot.custom_fields, '$.PAR Responsável atraso - Execução') AS responsible_execution_delay,
    GET_JSON_OBJECT(ot.custom_fields, '$.PAR Responsável pela reprovação') AS responsible_disapproval,
    GET_JSON_OBJECT(ot.custom_fields, '$.PAR Forma de pagamento') AS payment_format,
    GET_JSON_OBJECT(ot.custom_fields, '$.Ocorrências') AS occurrences,
    GET_JSON_OBJECT(ot.custom_fields, '$.Avaliação Interna') AS internal_evaluation,
    GET_JSON_OBJECT(ot.custom_fields, '$.PAR Tipo de reparos') AS repair_type,
    GET_JSON_OBJECT(ot.custom_fields, '$.PAR Frente de Reparos') AS repair_front,
    GET_JSON_OBJECT(ot.custom_fields, '$.PAR Tipo de Demanda') AS demand_type,
    GET_JSON_OBJECT(ot.custom_fields, '$.PAR Ocorrências do Prestador') AS ps_occurrences,
    GET_JSON_OBJECT(ot.custom_fields, '$.PAR Tipo de Solicitação') AS request_type,
    GET_JSON_OBJECT(ot.custom_fields, '$.Ocorrências') AS occurrence_type,
    COALESCE(
        GET_JSON_OBJECT(ot.custom_fields, '$.Atraso na Orçamentação 5A'),
        GET_JSON_OBJECT(ot.custom_fields, '$.Atraso na Orçamentação Parceiro'),
        GET_JSON_OBJECT(ot.custom_fields, '$.Atraso na Orçamentação Cliente')
    ) AS reason_budget_delay,
    COALESCE(
        GET_JSON_OBJECT(ot.custom_fields, '$.Atraso na Execução 5A'),
        GET_JSON_OBJECT(ot.custom_fields, '$.Atraso na Execução Parceiro'),
        GET_JSON_OBJECT(ot.custom_fields, '$.Atraso na Execução Cliente')
    ) AS reason_execution_delay,
    COALESCE(
        GET_JSON_OBJECT(ot.custom_fields, '$.Atraso na Agendamento 5A'),
        GET_JSON_OBJECT(ot.custom_fields, '$.Atraso na Agendamento Parceiro'),
        GET_JSON_OBJECT(ot.custom_fields, '$.Atraso na Agendamento Cliente')
    ) AS reason_scheduling_delay,
    CAST(
        CASE
            WHEN GET_JSON_OBJECT(ot.custom_fields, '$.PAR Prestador respondeu?') = 'não_respondeu' THEN FALSE
            WHEN GET_JSON_OBJECT(ot.custom_fields, '$.PAR Prestador respondeu?') = 'sim_respondeu' THEN TRUE
            ELSE NULL
        END AS BOOLEAN
    ) AS is_ps_replied,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR CSI') AS BOOLEAN) AS is_csi,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Iniciar Tratativa Reparo') AS BOOLEAN) AS is_repair_negotiations_started,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Vídeos ou fotos anexados') AS BOOLEAN) AS is_photos_videos_attached,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Data de disponibilidade coletada com IQ') AS BOOLEAN) AS is_availability_date_collected,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Aguardando envio da solicitação ao prestador') AS BOOLEAN) AS is_waiting_request_sent_to_ps,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Aguardando devolução do orçamento pelo PS') AS BOOLEAN) AS is_waiting_budget_returned_by_ps,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Foi feito o 1º FUP de orçamentação com o PS') AS BOOLEAN) AS is_first_budgeting_fup_ps_made,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Foi feito o 2º FUP de orçamentação com o PS') AS BOOLEAN) AS is_second_budgeting_fup_ps_made,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Cancelado na fase de orçamentação') AS BOOLEAN) AS is_in_budgeting_phase_canceled,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Será necessária visita de orçamentação') AS BOOLEAN) AS is_budget_visit_required,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Visita de orçamentação agendada') AS BOOLEAN) AS is_budget_visit_scheduled,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Visita realizada') AS BOOLEAN) AS is_visit_made,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Houve reagendamento da visita de orçamentação') AS BOOLEAN) AS is_budget_visit_rescheduled,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Orçamento recebido') AS BOOLEAN) AS is_budget_received,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Esse orçamento foi enviado dentro de 48h?') AS BOOLEAN) AS is_budget_sent_in_sla,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Aguardando Aprovação do Orçamento pelo PP') AS BOOLEAN) AS is_waiting_budget_approval_by_pp,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Orçamento Aprovado') AS BOOLEAN) AS is_budget_approved,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Ticket em espera') AS BOOLEAN) AS is_ticket_on_hold,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Data de início da espera') AS BOOLEAN) AS is_start_waiting_period,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Serviço agendado - NOVO') AS BOOLEAN) AS is_service_scheduled,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Foi feito FUP de execução com o PS') AS BOOLEAN) AS is_fup_execution_done_by_ps,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Reparo realizado (apenas reparo que foi orçado)') AS BOOLEAN) AS is_budgeted_repair_executed,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Envio das fotos/vídeos de conclusão') AS BOOLEAN) AS is_final_photos_videos_sent,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Orçamento Reprovado') AS BOOLEAN) AS is_budget_disapproved,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Ticket Finalizado') AS BOOLEAN) AS is_ticket_finalized,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Reparo realizado') AS BOOLEAN) AS is_repair_performed,
    CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Garantia de serviço') AS BOOLEAN) AS is_service_guarantee,
    DATE(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Data da disponibilidade do IQ 1')) AS dt_first_available,
    DATE(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Data da disponibilidade do IQ 2')) AS dt_second_available,
    DATE(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Data da disponibilidade do IQ 3')) AS dt_third_available,
    DATE(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Data de envio da solicitação de orçamento')) AS dt_budget_request_submitted,
    DATE(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Data do cancelamento')) AS dt_canceled,
    DATE(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Data de envio do ticket ao time de agendamento de visita')) AS dt_submission_visit_scheduling_team,
    DATE(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Data de agendamento da visita')) AS dt_visit_schedule,
    DATE(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Data em que ocorrerá a visita')) AS dt_visit,
    DATE(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Data de realização da visita')) AS dt_visit_took_place,
    DATE(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Data de solicitação do reagendamento')) AS dt_rescheduling_request,
    DATE(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Data de envio do orçamento pelo PS')) AS dt_budget_submission_by_ps,
    DATE(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Data de envio do orçamento a CX')) AS dt_budget_submission_to_cx,
    DATE(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Data da comunicação de aprovação de CX para Parceiros')) AS dt_cx_approval_communication_for_ps,
    DATE(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Data do inicio do contato para agendamento do serviço')) AS dt_contact_scheduling_service_started,
    DATE(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Data do agendamento do serviço')) AS dt_service_appointment,
    DATE(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Data em que o serviço será iniciado')) AS dt_service_started,
    DATE(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Data de envio das fotos/vídeos')) AS dt_photos_videos_submission,
    DATE(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Data de finalização do reparo')) AS dt_repair_completion,
    DATE(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Data de solicitação do adicional')) AS dt_additional_request,
    DATE(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Data de retorno de CX com a reprovação')) AS dt_cx_disapproval_returned,
    DATE(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Data de resolução do ticket')) AS dt_ticket_resolution,
    ots.dt_created AS dt_solicitation_iq,
    ot.dt_created
FROM
    ongoing_tickets ot
LEFT JOIN
    ongoing_tickets ots
        ON CAST(GET_JSON_OBJECT(ot.custom_fields, '$.PAR Ticket de CX') AS BIGINT) = ots.id_ticket