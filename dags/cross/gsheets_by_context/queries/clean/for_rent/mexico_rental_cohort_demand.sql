SELECT
    city_group,
    funnel_flow,
    target_ca,
    target_cep,
    target_cs,
    target_ds,
    target_es,
    target_oa,
    target_os,
    target_vb,
    target_vc,
    visao AS vision,
    week_origin,
    BOOLEAN(guarantee) AS has_guarantee,
    TO_DATE(week, 'yyyy-MM-dd') AS dt_week_started
FROM
    datalake_gsheets_raw.mexico_rental_cohort_demand