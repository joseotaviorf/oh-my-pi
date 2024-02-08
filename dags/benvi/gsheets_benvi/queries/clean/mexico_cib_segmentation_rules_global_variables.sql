SELECT
    INT(shorter_months_calculation),
    INT(longer_months_calculation),
    DATE(dt_modification)
FROM
    datalake_gsheets_raw.mexico_cib_segmentation_rules_global_variables
