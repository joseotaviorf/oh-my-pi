SELECT
    id,
    card_id,
    dashboard_id,
    "sizeX",
    "sizeY",
    "row",
    col,
    parameter_mappings,
    visualization_settings,
    created_at,
    updated_at,
    EXTRACT(year FROM updated_at)::INT AS year,
    EXTRACT(month FROM updated_at)::INT AS month,
    EXTRACT(day FROM updated_at)::INT AS day
FROM
    metabase."report_dashboardcard"
WHERE 
    EXTRACT(year FROM updated_at) = {year}
    AND EXTRACT(month FROM updated_at) = {month}
    AND EXTRACT(day FROM updated_at) = {day}
