SELECT 
    ft.sk_ticket ,
    (( ft.full_resolution_time ) / (60*24.0)) <= sla_in_days AS is_sla,
    ts.contact_theme_tag,
    ts.contact_theme_detail_tag
FROM 
    customer_support.fact_ticket ft 
JOIN
    customer_support.dim_taxonomy dt 
        ON ft.sk_taxonomy = dt.sk_taxonomy 
JOIN 
    customer_support.dim_department dd 
        ON ft.sk_main_department = dd.sk_department
JOIN 
    datalake_gsheets_clean_prod.taxonomy_sla ts
        ON dt.theme_detail = ts.contact_theme_detail_tag 
        AND dd.journey_step = ts.journey_step 
WHERE
    ft.front_or_back = 'back'
    AND dt.theme_detail IS NOT NULL