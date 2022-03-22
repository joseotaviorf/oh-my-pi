WITH tickets AS (
    SELECT DISTINCT
        e.id_ticket,
        GET_JSON_OBJECT(e.custom_fields, '$.Código do Contrato') as id_contract,
        GET_JSON_OBJECT(e.custom_fields, '$.Código do Imóvel') as id_house,
        'email' AS channel,
        e.agent_email,
        e.agent_name,
        e.agent_company,
        e.department,
        GET_JSON_OBJECT(e.custom_fields, '$.Tipo de Demanda') AS demand_type,
        GET_JSON_OBJECT(e.custom_fields, '$.Tipo de processo') AS process_type,
        GET_JSON_OBJECT(e.custom_fields, '$.Tipo de Cliente') AS client_type,
        GET_JSON_OBJECT(e.custom_fields, '$.O cliente é?') AS client_description,
        GET_JSON_OBJECT(e.custom_fields, '$.Reparos enviados ao PP') AS repairs_sent_pp,
        GET_JSON_OBJECT(e.custom_fields, '$.Reanalise de Reparos') AS reanalysis_repairs,
        GET_JSON_OBJECT(e.custom_fields, '$.Interação com PP') AS interaction_pp,
        GET_JSON_OBJECT(e.custom_fields, '$.Orçamentação Realizada') AS budgeting_performed,
        GET_JSON_OBJECT(e.custom_fields, '$.Orçamentação enviada ao PP') AS budgeting_sent_pp,
        GET_JSON_OBJECT(e.custom_fields, '$.Orçamentação enviada ao IQ') AS budgeting_sent_iq,
        GET_JSON_OBJECT(e.custom_fields, '$.Intermediação com as partes') AS intermediation_with_parties,
        GET_JSON_OBJECT(e.custom_fields, '$.Execução de Acordo') AS agreement_execution,
        GET_JSON_OBJECT(e.custom_fields, '$.Finalização') AS finishing,
        GET_JSON_OBJECT(e.custom_fields, '$.Valor da Orçamentação') AS budget_value,
        GET_JSON_OBJECT(e.custom_fields, '$.Faixa da Orçamentação') AS budget_range,
        GET_JSON_OBJECT(e.custom_fields, '$.Conclusão da Reanalise de Reparos') AS tags,
        GET_JSON_OBJECT(e.custom_fields, '$.Acordo entre as partes')AS agreement_between_parties,
        e.is_solved,
        DATE(GET_JSON_OBJECT(e.custom_fields, '$.[Data] Comunicação enviada ao IQ')) AS dt_communicated_iq,
        DATE(GET_JSON_OBJECT(e.custom_fields, '$.[Data] Intermediação com as partes')) AS dt_intermediate,
        DATE(GET_JSON_OBJECT(e.custom_fields, '$.[Data] Execução do acordo')) AS dt_agreement_executed,
        DATE(GET_JSON_OBJECT(e.custom_fields, '$.[Data] Finalização')) AS dt_finished,
        DATE(GET_JSON_OBJECT(e.custom_fields, '$.Data para retorno')) AS dt_return, 
        DATE(GET_JSON_OBJECT(e.custom_fields, '$.[Data] Orçamentação realizada ')) AS dt_budgeted,
        DATE(GET_JSON_OBJECT(e.custom_fields, '$.[Data] Reparos enviados ao PP')) AS dt_analysis,
        DATE(GET_JSON_OBJECT(e.custom_fields, '$.[Data] Reanalise de Reparos')) AS dt_reanalysis,
        DATE(e.ts_ticket_started) AS dt_started,
        DATE(e.ts_ticket_ended) AS dt_closed
    FROM 
        datalake_customer_support.email e
    WHERE 
        e.department IN ('Offboarding Reparos [OFF] [POS] [BACK]','Offboarding [OFF] [POS] [BACK]','B2B [POS] [OFF] [BACK]','Rescisão Prime [Casa Mineira]','B2B Prime [OFF] [POS] [BACK]')
),
last_ticket_in_contract AS (
    SELECT 
        MAX(id_ticket) OVER (PARTITION BY id_contract ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS id_ticket
    FROM 
        tickets t
    WHERE 
        t.client_type IN ('proprietário','imobiliária_b2b')
        AND t.process_type = 'reparos'
)
SELECT 
    t.*
FROM 
    tickets t
INNER JOIN
    last_ticket_in_contract ltic
        ON t.id_ticket = ltic.id_ticket