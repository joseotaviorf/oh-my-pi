SELECT
    backtest_id AS id_backtest,
    backtest_run_id AS id_run_backtest,
    sales_flow_id AS id_sales_flow,
    validation_id,
    assessment_target,
    validation_status,
    assessment_status,
    assessment_consolidated_status,
    backtest_concordance,
    contract_created_at AS ts_analysis_start,
    contract_updated_at AS ts_analysis_end
FROM
    datalake_legalops_raw.lego_backtest_results
