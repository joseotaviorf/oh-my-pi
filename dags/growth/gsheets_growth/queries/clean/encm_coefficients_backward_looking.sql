SELECT 
    STRING(NULLIF(city_group,'')) AS city_group,
    STRING(NULLIF(business_context,'')) AS business_context,
    STRING(NULLIF(event_name,'')) AS event_name,
    FLOAT(NULLIF(coefficient,'')) AS coefficient,
    FLOAT(NULLIF(constant,'')) AS constant,
    FLOAT(NULLIF(gross_takerate,'')) AS gross_takerate,
    FLOAT(NULLIF(survival_curve,'')) AS survival_curve,
    DATE(NULLIF(date_start, '')) AS date_start, 
    DATE(NULLIF(date_end, '')) AS date_end
FROM datalake_gsheets_raw.encm_coefficients_backward_looking