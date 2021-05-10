SELECT
    ui.id,
    ui.id_tof_user,
    ui.year,
    ui.month,
    ui.day
FROM
    datalake_top_of_funnel_demand.user_interactions ui
    LEFT JOIN datalake_top_of_funnel_demand.first_user_interaction fui
        ON ui.id_tof_user = fui.id_tof_user
WHERE
    ui.year = {year}
    AND ui.month = {month}
    AND ui.day = {day} 
    AND fui.id_tof_user IS NULL