SELECT 
    STRING(NULLIF(city_group,'')) AS city_group,
    STRING(NULLIF(business_context,'')) AS business_context,
    STRING(NULLIF(event_name,'')) AS event_name,
    STRING(NULLIF(price_range,'')) AS price_range,
    FLOAT(NULLIF(prob_conv,'')) AS prob_conv,
    FLOAT(NULLIF(tm_conv,'')) AS tm_conv,
    FLOAT(NULLIF(min_range,'')) AS min_range,
    FLOAT(NULLIF(max_range,'')) AS max_range,
    DATE(NULLIF(date_start, '')) AS date_start, 
    DATE(NULLIF(date_end, '')) AS date_end
FROM datalake_gsheets_raw.encm_conversion_probability