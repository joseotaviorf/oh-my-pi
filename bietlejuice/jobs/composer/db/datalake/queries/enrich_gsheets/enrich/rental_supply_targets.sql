SELECT
    *
FROM
    datalake_static_files.rental_supply_targets
UNION ALL
SELECT
    *
FROM
    datalake_gsheets_clean.supply_targets_2022