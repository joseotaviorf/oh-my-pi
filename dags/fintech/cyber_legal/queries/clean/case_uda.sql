SELECT
    CUCASENO AS id_case,
    CUPOSSIB AS cause_loss_possibility_code,
    CUVARA AS court_division_name,
    CUCOMARC AS judicial_district_name,
    CUSUBTIP AS process_subtype,
    CULOV AS lov_code,
    CUDECIMAL AS decimal_value,
    CUVALREC AS provisioned_amount,
    CUVLTTCAUSA AS updated_cause_value_amount,
    CUPEMULT AS procedural_fine_amount,
    CUPEHONO AS contingency_fee_amount,
    CUDATE AS dt_notified,
    CUREVGERAL AS dt_last_general_review,
    CUULTDT AS dt_last_movement,
    NOW() AS ts_load
FROM datalake_cyber_legal_homolog_raw.caseuda
