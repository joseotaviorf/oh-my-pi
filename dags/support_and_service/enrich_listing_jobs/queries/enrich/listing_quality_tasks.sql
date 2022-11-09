SELECT
    CAST(tf.id_job AS BIGINT) AS id_photo_job,
    CAST(GET_JSON_OBJECT(tf.custom_fields, '$["[AQ] ID do imóvel"]') AS BIGINT) AS id_house,
    tf.id_ticket,
    GET_JSON_OBJECT(tf.custom_fields, '$["[AQ] Nome do analista"]') AS responsible_analyst_name,
    GET_JSON_OBJECT(tf.custom_fields, '$["[AQ] User_sender"]') AS user_sender,
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
    tf.ts_updated AS dt_analyzed_utc,
    tf.ts_updated_local AS dt_analyzed
FROM
    datalake_zendesk_ticket_funnels.ticket_funnel tf
WHERE
    tf.group_name = 'Listing Quality [FOTOS] [SO]'
    AND tf.subject LIKE 'Listing Quality - %'
    AND DATE(tf.ts_updated) >= DATE("2022-06-11")
UNION ALL
SELECT
    aux.id_photo_job,
    aux.id_house,
    NULL AS id_ticket,
    aux.analyzed_by AS responsible_analyst_name,
    aux.final_user_sender AS user_sender,
    aux.final_classification AS house_classification,
    SPLIT(aux.final_classification_reason, ";") AS house_classification_reason,
    aux.final_classification_comments AS classification_comments,
    aux.sign_placement AS signboard_location,
    NULL AS dt_analyzed_utc,
    aux.dt_analyzed
FROM
    datalake_gsheets_clean.aux_check_photo_sender aux