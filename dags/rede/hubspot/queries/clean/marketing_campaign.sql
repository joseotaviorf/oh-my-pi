SELECT
    id::BIGINT AS id_marketing_campaign,
    appId::INT AS id_app,
    contentId::BIGINT AS id_content,
    appName AS app_name,
    subject,
    name,
    processingState AS processing_state,
    type,
    FROM_JSON(counters, 'map<string, int>') AS counters,
    numIncluded::INT AS num_included,
    TO_TIMESTAMP(NULLIF(lastProcessingStartedAt/1000, 0)) AS ts_last_processing_started,
    TO_TIMESTAMP(NULLIF(lastProcessingFinishedAt/1000, 0)) AS ts_last_processing_finished,
    TO_TIMESTAMP(NULLIF(lastProcessingStateChangeAt/1000, 0)) AS ts_last_processing_state_change
FROM
    datalake_hubspot_raw.marketing_campaign
