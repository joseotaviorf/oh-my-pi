SELECT
    macro_taxonomy,
    micro_taxonomy,
    journey,
    sub_journey,
    line_owner,
    micro_taxonomy_description,
    ops_focal_point,
    is_active,
    NOW() AS ts_snapshot,
    YEAR(NOW()) AS year,
    MONTH(NOW()) AS month,
    DAY(NOW()) AS day
FROM
    datalake_gsheets_clean.ticket_rate_classification
