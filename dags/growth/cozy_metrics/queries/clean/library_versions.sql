SELECT 
    name AS metric_name,
    project AS project_name,
    project_version,    
    replace(value:["@quintoandar/cozy-core"],'^','') AS core,
    replace(value:["@quintoandar/cozy-icons"],'^','') AS icons,
    replace(value:["@quintoandar/cozy-theme"],'^','') AS theme,
    replace(value:["@quintoandar/cozy-tokens"],'^','') AS tokens,
    replace(value:["@quintoandar/cozy-utils"],'^','') AS utils,
    DATE(created_at) as dt_created
FROM datalake_cozy_metrics_raw.library_versions