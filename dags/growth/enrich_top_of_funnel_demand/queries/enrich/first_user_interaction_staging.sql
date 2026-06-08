SELECT
    ui.id,
    ui.id_tof_user,
    ui.business_context,
    ui.year,
    ui.month,
    ui.day
FROM
    datalake_top_of_funnel_demand.user_interactions ui
    LEFT JOIN datalake_top_of_funnel_demand.first_user_interaction fui
        ON ui.id_tof_user = fui.id_tof_user
        AND ui.business_context = fui.business_context
WHERE
    MAKE_DATE(ui.year, ui.month, ui.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND fui.id_tof_user IS NULL