SELECT
    schema_table,
    entity_path,
    sample_values_entities_found,
    column_name_entities_found,
    initial_eval,
    manual_eval,
    "Check (DPE)" AS dpe_check,
    "Check (Privacy)" AS privacy_check,
    Comment,
    test_value_category,
    test_column_category,
    test_initial_eval,
    teste_false_positive,
    teste_false_negative,
    "Comment (Privacy)" comment_from_privacy
FROM datalake_gsheets_raw.scan_clean_evaluation