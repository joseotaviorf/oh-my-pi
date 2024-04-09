WITH base AS (WITH filtered_custom_fields AS (
    SELECT
        tck.id_ticket,
        EXPLODE(SPLIT(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REGEXP_REPLACE(tck.custom_fields, '"(?!")', ''), 'id:', ''), ',value', ''), '[', ''), ']', ''), '{{', ''), '}},')) AS custom_field
    FROM
        datalake_velo_zendesk_clean.tickets AS tck
 ),
 parsed_custom_fields AS (
    SELECT DISTINCT
        id_ticket,
        SPLIT(custom_field, ':')[0] AS id_custom_field,
        SPLIT(custom_field, ':')[1] AS custom_field_value,
        CASE
            WHEN SPLIT(custom_field, ':')[0] = 25411571630100 THEN 'Valor inadimplente (pago à imob)'
            WHEN SPLIT(custom_field, ':')[0] = 25339446197780 THEN 'Valor inadimplente (pago à imob) 1'
            WHEN SPLIT(custom_field, ':')[0] = 7259632296468 THEN 'Valor inadimplente (pago à imob) 2'
            ELSE tf.raw_title
        END AS custom_field_title
    FROM
        filtered_custom_fields AS tcf
    JOIN
        datalake_velo_zendesk_clean.ticket_fields AS tf
            ON tf.id_ticket_fields = SPLIT(custom_field, ':')[0]
    WHERE
        NULLIF(NULLIF(REPLACE(REPLACE(SPLIT(custom_field, ':')[1], '\"}}', ''),'"', ''), ''), 'null') IS NOT NULL
)
SELECT
    id_ticket,
    MAP_FROM_ARRAYS(COLLECT_LIST(custom_field_title), COLLECT_LIST(custom_field_value)) AS custom_fields
FROM
    parsed_custom_fields
GROUP BY 1
)
    SELECT
        base.id_ticket,
        COALESCE(base.custom_fields['ID da proposta do inquilino'], base.custom_fields['ID da Proposta']) AS id_propose,
        base.custom_fields['ID da Delinquency'] AS id_delinquency,
        base.custom_fields['Erros de Solicitação '] AS request_error,
        COALESCE(base.custom_fields['Tipo de Solicitação'], base.custom_fields['Prazo de recebimento']) AS request_type,
        base.custom_fields['Motivo do cancelamento '] AS cancellation_reason,
        base.custom_fields['Nome da imobiliária '] AS broker_name,
        base.custom_fields['Motivo de Contato'] AS contact_reason,
        base.custom_fields['Nome do inquilino'] AS tenant_name,
        base.custom_fields['Solicitação do Cliente'] AS client_request,
        COALESCE(base.custom_fields['Valor inadimplente (pago à imob)'],base.custom_fields['Valor inadimplente (pago à imob) 1'],base.custom_fields['Valor inadimplente (pago à imob) 2'], base.custom_fields['Overdue amount']) AS overdue_amount,
        base.custom_fields['Acionamento de garantia'] AS guarantee_activation,
        base.custom_fields['Encaminhado para Pagamento'] AS has_payment_forwarded,
        CAST(base.custom_fields['Retorno a Acionamento'] AS DATE) AS dt_request_return,
        CAST(base.custom_fields['Pré tombamento'] AS DATE) AS dt_submission,
        CAST(base.custom_fields['Data de vencimento original'] AS DATE) AS dt_due_original,
        CAST(base.custom_fields['Data início da tratativa'] AS DATE) AS dt_started,
        CAST(base.custom_fields['Data em que o pagamento será realizado'] AS DATE) AS dt_payment_scheduled,
        CAST(base.custom_fields['Data de encaminhamento pagamento'] AS DATE) AS dt_payment_forwarded
    FROM
        base
