WITH get_policy_report_income_engine_data AS (
  SELECT
    id AS id_policy_report,
    id_external AS id_proposal,
    type AS policy_name,
    GET_JSON_OBJECT(result, '$.elected_income_sum') AS proposal_elected_income_sum,
    GET_JSON_OBJECT(result, '$.declared_income_sum') AS proposal_declared_income_sum,
    GET_JSON_OBJECT(result, '$.has_exception') AS proposal_has_exception,
    ARRAY_SIZE(
      FROM_JSON(
        GET_JSON_OBJECT(raw_data, '$.tenants'),
        'ARRAY<STRING>'
      )
    ) AS number_of_tenants,
    raw_data,
    version,
    ts_created,
    ts_updated
  FROM
    datalake_sorting_hat_clean.policy_report -- Filtering only the income engine data
  WHERE
    type = 'TENANT_INCOME'
),
extract_json_tenants_data AS (
  SELECT
    id,
    EXPLODE_OUTER(
      FROM_JSON(
        GET_JSON_OBJECT(raw_data, '$.tenants'),
        'ARRAY<
                    STRUCT<
                        analysis_machine_id: INTEGER,
                        analysis_request_id: INTEGER,
                        aggregated_structured_results: STRING
                    >
                >'
      )
    ) AS extract_json
  FROM
    datalake_sorting_hat_clean.policy_report
  WHERE
    type = 'TENANT_INCOME'
),
get_tenants_data AS (
  SELECT
    id,
    extract_json.analysis_machine_id AS id_analysis_machine,
    extract_json.analysis_request_id AS id_analysis_request,
    GET_JSON_OBJECT(extract_json.aggregated_structured_results, '$.changes') AS tenant_changes,
    GET_JSON_OBJECT(extract_json.aggregated_structured_results, '$.scrIncome') AS tenant_scr_income,
    GET_JSON_OBJECT(extract_json.aggregated_structured_results, '$.isRetenant') AS is_retenant,
    GET_JSON_OBJECT(extract_json.aggregated_structured_results, '$.bureauIncome') AS tenant_bureau_income,
    GET_JSON_OBJECT(extract_json.aggregated_structured_results, '$.hasScrReport') AS tenant_has_scr_report,
    GET_JSON_OBJECT(extract_json.aggregated_structured_results, '$.electedIncome') AS tenant_elected_income,
    GET_JSON_OBJECT(extract_json.aggregated_structured_results, '$.incomeChanges') AS tenant_income_changes,
    GET_JSON_OBJECT(extract_json.aggregated_structured_results, '$.internalDebts') AS tenant_internal_debts,
    GET_JSON_OBJECT(extract_json.aggregated_structured_results, '$.declaredIncome') AS tenant_declared_income,
    GET_JSON_OBJECT(extract_json.aggregated_structured_results, '$.isDemotedGroup') AS is_demoted_group,
    GET_JSON_OBJECT(extract_json.aggregated_structured_results, '$.verifiedIncome') AS tenant_verified_income,
    GET_JSON_OBJECT(extract_json.aggregated_structured_results, '$.boavistaScoreP6') AS tenant_boavista_score_p6,
    GET_JSON_OBJECT(extract_json.aggregated_structured_results, '$.maxBureauIncome') AS tenant_max_bureau_income,
    GET_JSON_OBJECT(extract_json.aggregated_structured_results, '$.serasaScoreHspi') AS tenant_serasa_score_hspi,
    GET_JSON_OBJECT(extract_json.aggregated_structured_results, '$.homogeneousGroup') AS tenant_homogeneous_group,
    GET_JSON_OBJECT(extract_json.aggregated_structured_results, '$.netElectedIncome') AS tenant_net_elected_income,
    GET_JSON_OBJECT(extract_json.aggregated_structured_results, '$.transunionBook3d') AS tenant_transunion_book3d,
    GET_JSON_OBJECT(extract_json.aggregated_structured_results, '$.crivoIncomeReport') AS tenant_crivo_income_report,
    GET_JSON_OBJECT(extract_json.aggregated_structured_results, '$.neowayIncomeReport') AS tenant_neoway_income_report,
    GET_JSON_OBJECT(extract_json.aggregated_structured_results, '$.incomeVerifierScore') AS tenant_income_verifier_score,
    GET_JSON_OBJECT(extract_json.aggregated_structured_results, '$.bigdatacorpBasicData') AS tenant_bigdatacorp_basic_data,
    GET_JSON_OBJECT(extract_json.aggregated_structured_results, '$.boavistaPresumedIncome') AS tenant_boavista_presumed_income,
    GET_JSON_OBJECT(extract_json.aggregated_structured_results, '$.boavistaScoreVehicleV6') AS tenant_boavista_score_vehicle_v6,
    GET_JSON_OBJECT(extract_json.aggregated_structured_results, '$.boavistaScpcQueryCount') AS tenant_boavista_scpc_query_count,
    GET_JSON_OBJECT(extract_json.aggregated_structured_results, '$.bureauAndDeclaredRatio') AS tenant_bureau_and_declared_ratio,
    GET_JSON_OBJECT(extract_json.aggregated_structured_results, '$.internalDebtsOnDefault') AS tenant_internal_debts_on_default
  FROM
    extract_json_tenants_data
)

SELECT
  CAST(td.id_analysis_machine AS INTEGER) AS id_analysis_machine,
  CAST(td.id_analysis_request AS INTEGER) AS id_analysis_request,
  CAST(ied.id_policy_report AS INTEGER) AS id_policy_report,
  CAST(ied.id_proposal AS INTEGER) AS id_proposal,
  CAST(GET_JSON_OBJECT(td.tenant_boavista_score_p6, '$.id') AS INTEGER) AS id_boavista_score_p6,
  CAST(GET_JSON_OBJECT(td.tenant_serasa_score_hspi, '$.id') AS INTEGER) AS id_serasa_score_hspi,
  CAST(GET_JSON_OBJECT(td.tenant_transunion_book3d, '$.id') AS INTEGER) AS id_transunion_book3d,
  CAST(GET_JSON_OBJECT(td.tenant_neoway_income_report, '$.id') AS INTEGER) AS id_neoway_income_report,
  CAST(GET_JSON_OBJECT(td.tenant_bigdatacorp_basic_data, '$.id') AS INTEGER) AS id_bigdatacorp_basic_data,
  CAST(GET_JSON_OBJECT(td.tenant_boavista_score_vehicle_v6, '$.id') AS INTEGER) AS id_boavista_score_vehicle_v6,
  CAST(GET_JSON_OBJECT(td.tenant_boavista_scpc_query_count, '$.id') AS INTEGER) AS id_boavista_scpc_query_count,
  CAST(GET_JSON_OBJECT(td.tenant_crivo_income_report, '$.id') AS INTEGER) AS id_crivo_income_report,
  ied.policy_name,
  CAST(ied.proposal_elected_income_sum AS DECIMAL(10, 2)) AS proposal_elected_income_sum,
  CAST(ied.proposal_declared_income_sum AS DECIMAL(10, 2)) AS proposal_declared_income_sum,
  CAST(ied.number_of_tenants AS INTEGER) AS number_of_tenants,
  CAST(ied.version AS INTEGER) AS version,
  CAST(td.tenant_changes AS INTEGER) AS tenant_changes,
  CAST(td.tenant_bureau_income as DECIMAL(10, 2)) AS tenant_bureau_income,
  CAST(td.tenant_elected_income AS DECIMAL(10, 2)) AS tenant_elected_income,
  CAST(td.tenant_income_changes AS INTEGER) AS tenant_income_changes,
  CAST(td.tenant_internal_debts AS DECIMAL(10, 2)) AS tenant_internal_debts,
  CAST(td.tenant_declared_income AS DECIMAL(10, 2)) AS tenant_declared_income,
  CAST(td.tenant_verified_income AS DECIMAL(10, 2)) AS tenant_verified_income,
  CAST(GET_JSON_OBJECT(td.tenant_boavista_score_p6, '$.scoreP6') AS INTEGER) AS tenant_boavista_scoreP6,
  GET_JSON_OBJECT(td.tenant_boavista_score_p6, '$.integrationProvider') AS tenant_boavista_integration_provider,
  CAST(td.tenant_max_bureau_income AS DECIMAL(10, 2)) AS tenant_max_bureau_income,
  CAST(GET_JSON_OBJECT(td.tenant_serasa_score_hspi, '$.scoreHspi') AS INTEGER) AS tenant_serasa_score_hspi,
  GET_JSON_OBJECT(td.tenant_serasa_score_hspi, '$.integrationProvider') AS tenant_serasa_integration_provider,
  td.tenant_homogeneous_group,
  CAST(td.tenant_net_elected_income AS DECIMAL(10, 2)) AS tenant_net_elected_income,
  GET_JSON_OBJECT(td.tenant_transunion_book3d, '$.tempoEmissaoCpf') AS tenant_transunion_book3d_cpf_emission_time,
  GET_JSON_OBJECT(td.tenant_transunion_book3d, '$.classBancUltDecl') AS tenant_transunion_book3d_classBancUltDecl,
  GET_JSON_OBJECT(td.tenant_transunion_book3d, '$.integrationProvider') AS tenant_transunion_book3d_integration_provider,
  GET_JSON_OBJECT(td.tenant_transunion_book3d, '$.scPercentConsultas12Fin02') AS tenant_transunion_book3d_scPercentConsultas12Fin02,
  GET_JSON_OBJECT(td.tenant_crivo_income_report, '$.source') AS tenant_crivo_income_report_source,
  CAST(GET_JSON_OBJECT(td.tenant_crivo_income_report, '$.presumedIncome') AS DECIMAL(10, 2)) AS tenant_crivo_income_report_presumed_income,
  CAST(GET_JSON_OBJECT(td.tenant_crivo_income_report, '$.incomeRangeLowerValue') AS DECIMAL(10, 2)) AS tenant_crivo_income_report_income_range_lower_value,
  CAST(GET_JSON_OBJECT(td.tenant_crivo_income_report, '$.incomeRangeHigherValue') AS DECIMAL(10, 2)) AS tenant_crivo_income_report_income_range_higher_value,
  GET_JSON_OBJECT(td.tenant_neoway_income_report, '$.source') AS tenant_neoway_income_report_source,
  CAST(GET_JSON_OBJECT(td.tenant_neoway_income_report, '$.presumedIncome') AS DECIMAL(10, 2)) AS tenant_neoway_income_report_presumed_income,
  CAST(GET_JSON_OBJECT(td.tenant_neoway_income_report, '$.incomeRangeLowerValue') AS DECIMAL(10, 2)) AS tenant_neoway_income_report_income_range_lower_value,
  CAST(GET_JSON_OBJECT(td.tenant_neoway_income_report, '$.incomeRangeHigherValue') AS DECIMAL(10, 2)) AS tenant_neoway_income_report_income_range_higher_value,
  CAST(td.tenant_income_verifier_score AS INTEGER) AS tenant_income_verifier_score,
  CAST(GET_JSON_OBJECT(td.tenant_bigdatacorp_basic_data, '$.age') AS INTEGER) AS tenant_bigdatacorp_basic_data_tenant_age,
  GET_JSON_OBJECT(td.tenant_bigdatacorp_basic_data, '$.integrationProvider') AS tenant_bigdatacorp_basic_data_integration_provider,
  CAST(td.tenant_boavista_presumed_income AS DECIMAL(10, 2)) AS tenant_boavista_presumed_income,
  CAST(GET_JSON_OBJECT(td.tenant_boavista_score_vehicle_v6, '$.scoreVehicleV6') AS INTEGER) AS tenant_boavista_score_vehicle_v6,
  GET_JSON_OBJECT(td.tenant_boavista_score_vehicle_v6, '$.integrationProvider') AS tenant_boavista_score_vehicle_v6_integration_provider,
  CAST(GET_JSON_OBJECT(td.tenant_boavista_scpc_query_count, '$.scpcQueryCount') AS INTEGER) AS tenant_boavista_scpc_query_count,
  GET_JSON_OBJECT(td.tenant_boavista_scpc_query_count, '$.integrationProvider') AS tenant_boavista_scpc_query_count_integration_provider,
  CAST(td.tenant_bureau_and_declared_ratio AS DECIMAL(10, 2)) AS tenant_bureau_and_declared_ratio,
  CAST(td.tenant_internal_debts_on_default AS DECIMAL(10, 2)) AS tenant_internal_debts_on_default,
  CAST(td.tenant_scr_income AS DECIMAL(10, 2)) AS tenant_scr_income,
  CAST(td.tenant_has_scr_report AS BOOLEAN) AS has_scr_report,
  CAST(td.is_demoted_group AS BOOLEAN) AS is_demoted_group,
  CAST(td.is_retenant AS BOOLEAN) AS is_retenant,
  CAST(ied.proposal_has_exception AS BOOLEAN) AS proposal_has_exception,
  ied.ts_created,
  ied.ts_updated
FROM
  get_policy_report_income_engine_data AS ied
INNER JOIN
  get_tenants_data AS td
    ON ied.id_policy_report = td.id
