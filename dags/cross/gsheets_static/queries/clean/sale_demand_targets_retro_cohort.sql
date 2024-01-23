SELECT
    city_group,
    hub_offer,
    weeks_conversion,
    vb2vc,
    vc2os,
    os2oa,
    oa2ccv,
    ccv_signed,
    os2ccv,
    is_rede,
    TO_DATE(week_start, 'yyyy-MM-dd') AS dt_week_started
FROM
    datalake_gsheets_raw.sale_demand_targets_retro_cohort
