-- Current-state Product & Tech neotribe catalog; grain is one row per line × neotribe.
SELECT
    neotribe_catalog.id_line_neotribe AS sk_product_tech_neotribe,
    neotribe_catalog.line,
    neotribe_catalog.neotribe,
    neotribe_catalog.objective,
    neotribe_catalog.mission,
    neotribe_catalog.scope,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    datalake_gsheets_people_clean.product_tech_neotribe AS neotribe_catalog
