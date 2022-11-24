SELECT
    cost_definition,
    cost_funnel,
    cost_type,
    mkt_origin,
    relative_value_fr_fs,
    DATE(month_start) AS dt_month_started,
    DATE(month_end) AS dt_month_ended
FROM
    datalake_gsheets_raw.costs_allocation_relative_indexes