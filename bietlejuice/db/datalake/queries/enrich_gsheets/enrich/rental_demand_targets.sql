SELECT
    *
FROM
    datalake_static_files.rental_demand_targets
UNION ALL
SELECT
    *
FROM
    datalake_gsheets_clean.demand_targets_2022