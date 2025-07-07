SELECT
    tc.id_ticket,
    tc.id_job AS id_photo_job,
    COALESCE(tc.id_house_aq, REGEXP_EXTRACT(subject, '(\\d+)', 0)) AS id_house,
    tc.user_sender,
    tc.analyst_name AS responsible_analyst_name,
    tc.analyst_email AS responsible_analyst_email,
    tc.analyst_organization AS responsible_analyst_organization,
    tc.group_name,
    tc.house_classification,
    ARRAY_EXCEPT(
        ARRAY(
            tc.house_classification_reason1,
            tc.house_classification_reason2,
            tc.house_classification_reason3,
            tc.house_classification_reason4
        ),
        ARRAY(NULL)
    ) AS house_classification_reason,
    tc.video_comments AS classification_comments,
    tc.signboard_location,
    tc.status,
    tc.ts_created,
    tc.ts_created - INTERVAL 3 HOUR AS ts_created_local,
    tc.ts_updated AS dt_analyzed_utc,
    tc.ts_updated - INTERVAL 3 HOUR AS dt_analyzed
FROM
    datalake_zendesk.tickets_current AS tc
WHERE
    tc.group_name = 'Listing Quality [FOTOS] [SO]'
    AND DATE(tc.ts_created) >= DATE("2023-01-01")
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
