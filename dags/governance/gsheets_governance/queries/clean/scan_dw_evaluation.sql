SELECT
    schema_table,
    entity_path,
    sample_values_entities_found,	
    column_name_entities_found,	
    samples, 
    initial_eval,
    manual_eval,
    "Check (DPE)" as check_dpe,
    "Check (Privacy)" AS check_privacy,
    comment,
    test_value_category,
    test_column_category,
    test_initial_eval,	
    teste_false_positive,	
    teste_false_negative
FROM datalake_gsheets_raw.scan_dw_evaluation