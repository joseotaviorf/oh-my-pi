-- In this CTE we extract all taxonomy data available in Rene Descartes
SELECT 
    hl.id AS id_lead,
    hl.id_lead_ebdb,
    hl.id_external_reference AS id_firestore, -- This field will be deprecated by the P&T team
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.affiliateType') AS STRING) AS affiliate_type,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.utmCampaign') AS STRING) AS campaign,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.utmMedium') AS STRING) AS medium,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.utmSource') AS STRING) AS source,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.team') AS STRING) AS ops_agent, 
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.company') AS STRING) AS ops_partner,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.origin') AS STRING) AS application,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.cidade') AS STRING) AS city,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.referrer') AS STRING) AS landing_page,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.contactType') AS STRING) AS ops_approach,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.contactChannel') AS STRING) AS ops_contact_medium, 
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.platform') AS STRING) AS platform,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.type') AS STRING) AS lead_type,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.originalLead') AS BIGINT) AS original_lead,
    amd.ts_created AS ts_event,
    amd.year,
    amd.month,
    amd.day
FROM datalake_rene_descartes_clean.house_lead AS hl
LEFT JOIN datalake_rene_descartes_clean.acquisition_misc_data AS amd
    ON hl.id_acquisition = amd.id
WHERE DATE(amd.ts_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')