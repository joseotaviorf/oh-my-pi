SELECT
    INT(id_segmentation),
    name_segmentation,
    FLOAT(min_months_registered),
    FLOAT(max_months_registered),
    FLOAT(min_value_fl) AS min_fl,
    FLOAT(max_value_fl) AS max_fl,
    FLOAT(min_value_cs) AS min_cs,
    FLOAT(max_value_cs) AS max_cs,
    DATE(dt_modification)
FROM
    datalake_gsheets_raw.mexico_cib_segmentation_rules_segmentation_variables
