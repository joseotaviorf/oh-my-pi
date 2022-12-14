SELECT 
    project_name,
    CAST(SPLIT(core,'\\.')[0] AS BIGINT) as major_version,
    CAST(split(core,'\\.')[1] AS BIGINT) as minor_version,
    CAST(split(split(core,'\\.')[2],'-')[0] AS BIGINT) as patches,
    CASE
        WHEN project_name 
            IN (
            'agents-pwa','photos-pwa','jarvis-pwa','inspetor-bugiganga',
            'b2b-lite-pwa','rental-guarantee-platform-pwa','secretariat-pwa',
            'photos-pwa'
            ) THEN 'partner'
        WHEN project_name
            IN ( 
            'julius', 'seumadruga-pwa', 'sitemap-pwa', 'pwa-template', 'sales-flow-pwa', 'monopoly-pwa',
            'payments-pwa', 'user-segmentation-pwa', 'hogwarts-pwa', 'simba-pwa', 'crm-pwa', 
            'owner-conversion-pwa','secretariat-pwa', 'crm-pwa-imoveis', 'agents-crm-pwa',
            'cozy-pwa', '5a-pwa-template', 'pwa-template'
            ) THEN 'internal'
        ELSE
            'end-user'
    END AS type_of_pwa,
    IF(CAST(split(core,'.')[1] AS BIGINT) >= 19, true, false) as is_updated_v19,
    dt_created
FROM datalake_cozy_metrics_clean.library_versions