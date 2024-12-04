SELECT DISTINCT
    journey_step,
    contact_theme_detail_tag AS theme_detail,
    sla_in_days AS sla,
    dt_start,
    dt_end
FROM
    datalake_gsheets_clean.taxonomy_sla
WHERE
    dt_target_invalidated IS NULL
