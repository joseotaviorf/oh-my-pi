SELECT
    COALESCE(amu.id_amplitude_merged, damcs.id_amplitude) AS id_amplitude,
    id_session,
    ep_house_id AS id_house,
    GET_JSON_OBJECT(user_properties, '$.country') AS country_code,
    damcs.country AS user_country,
    up_utm_source AS utm_source,
    up_utm_medium AS utm_medium,
    up_utm_campaign AS utm_campaign,
    up_utm_content AS utm_content,
    up_utm_term AS utm_term,
    ts_event
FROM datalake_amplitude_clean.`170698_contract_docusign_signed_events` damcs
LEFT JOIN datalake_amplitude_clean.`170698_user_merge` amu
    ON damcs.id_amplitude = amu.id_amplitude
WHERE DATE(CAST(damcs.year AS STRING) || '-' || CAST(damcs.month AS STRING) || '-' || CAST(damcs.day AS STRING)) >= CURRENT_DATE - INTERVAL '3' month
    AND platform = 'Web'
GROUP BY 11,1,2,3,4,5,6,7,8,9,10
