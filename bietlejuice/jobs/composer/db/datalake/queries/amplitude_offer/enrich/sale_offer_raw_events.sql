SELECT
    id_user,
    '170698' AS id_app,
    id_house,
    id_offer,
    app_type,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_content,
    utm_term,
    CASE
        WHEN (UPPER(utm_campaign) LIKE '%BRANDED%'
        OR UPPER(utm_campaign) LIKE '%INSTITUCIONAL%')
        AND UPPER(utm_campaign) NOT LIKE '%NON-BRANDED%'
            THEN 'Branded'
        ELSE 'Outro'
    END AS branded,
    COALESCE(((UPPER(utm_campaign) LIKE '%BRANDED%'
        OR UPPER(utm_campaign) LIKE '%INSTITUCIONAL%')
        AND LOWER(utm_campaign) NOT LIKE '%non-branded%'), FALSE) AS is_branded,
    ts_event
FROM
    datalake_amplitude_clean.170698_sale_offer_form_accepted