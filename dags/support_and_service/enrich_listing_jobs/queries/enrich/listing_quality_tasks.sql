SELECT
    tf.id_ticket,
    tf.id_job AS id_photo_job,
    COALESCE(GET_JSON_OBJECT(tf.custom_fields, '$["[AQ] ID do imóvel"]'), REGEXP_EXTRACT(subject, '(\\d+)', 0)) AS id_house,
    GET_JSON_OBJECT(tf.custom_fields, '$["[AQ] User_sender"]') AS user_sender,
    tf.agent_name AS responsible_analyst_name,
    tf.agent_email AS responsible_analyst_email,
    tf.agent_organization AS responsible_analyst_organization,
    tf.group_name,
    GET_JSON_OBJECT(tf.custom_fields, '$["[AQ] Classificação do Imóvel"]') AS house_classification,
    ARRAY_EXCEPT(
        ARRAY(
            GET_JSON_OBJECT(tf.custom_fields, '$["[AQ] Motivo da Classificação do Imóvel 1"]'),
            GET_JSON_OBJECT(tf.custom_fields, '$["[AQ] Motivo da Classificação do Imóvel 2"]'),
            GET_JSON_OBJECT(tf.custom_fields, '$["[AQ] Motivo da Classificação do Imóvel 3"]'),
            GET_JSON_OBJECT(tf.custom_fields, '$["[AQ] Motivo da Classificação do Imóvel 4"]')
        ),
        ARRAY(NULL)
    ) AS house_classification_reason,
    GET_JSON_OBJECT(tf.custom_fields, '$["[AQ] Comentários"]') AS classification_comments,
    GET_JSON_OBJECT(tf.custom_fields, '$["[AQ] Tem plaquinha"]') AS signboard_location,
    tf.status,
    tf.ts_created,
    tf.ts_created_local,
    tf.ts_updated AS dt_analyzed_utc,
    tf.ts_updated_local AS dt_analyzed
FROM
    datalake_zendesk_ticket_funnels.ticket_funnel AS tf
WHERE
    tf.group_name = 'Listing Quality [FOTOS] [SO]'
    AND DATE(tf.ts_created) >= DATE("2023-01-01")
UNION ALL
SELECT
    NULL AS id_ticket,
    aux.id_photo_job,
    aux.id_house,
    aux.final_user_sender AS user_sender,
    aux.analyzed_by AS responsible_analyst_name,
    NULL AS responsible_analyst_email,
    NULL AS responsible_analyst_organization,
    NULL AS group_name,
    aux.final_classification AS house_classification,
    SPLIT(aux.final_classification_reason, ";") AS house_classification_reason,
    aux.final_classification_comments AS classification_comments,
    aux.sign_placement AS signboard_location,
    NULL AS status,
    NULL AS ts_created,
    NULL AS ts_created_local,
    NULL AS dt_analyzed_utc,
    aux.dt_analyzed
FROM
    datalake_gsheets_clean.aux_check_photo_sender aux