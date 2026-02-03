WITH
get_external_id_contract AS (
    SELECT DISTINCT
        id_contract_external,
        id_contract,
        contract_status,
        eviction_step,
        eviction_law_firm,
        reason_eviction
    FROM datalake_cyber_legal_homolog_clean.contracts
),
get_last_delqmst_data AS (
    SELECT
        id_contract,
        flag_account_in_agency_or_court,
        evictions_label,
        ts_last_update,
        ts_last_activity
        -- MAKE_DATE(year,month,day) AS partition
    FROM datalake_cyber_legal_homolog_clean.delinquent_master
    QUALIFY ROW_NUMBER() OVER(PARTITION BY id_contract ORDER BY ts_last_update DESC) = 1
)
SELECT
    c.id_case,
    cacct.id_contract AS id_contract_cyber,
    ct.id_contract_external AS id_contract,
    c.id_dossier AS id_process,
    c.id_court,
    crt.court_name,
    CASE
        WHEN c.process_type = "Despejo" THEN "EVICTIONS"
        WHEN c.process_type = "Execucao" THEN "EXECUTION"
        WHEN c.process_type = "Reivindicatoria" THEN "CLAIM"
        ELSE c.process_type
    END AS process_type,
    c.id_attorney_agency AS id_agency,
    ag.agency_name,
    c.id_responsible_attorney AS internal_lawyer,
    c.id_external_attorney AS external_lawyer,
    c.id_supervisor_attorney AS supervising_lawyer,
    c.city,
    c.state,
    ct.contract_status,
    dq.flag_account_in_agency_or_court AS contract_evictions_status,
    dq.evictions_label,
    ct.eviction_step,
    ct.eviction_law_firm,
    ct.reason_eviction,
    cntf.request_comment AS process_start_comment,
    c.close_comment AS process_end_comment,
    c.case_comment,
    c.case_status,
    cuda.process_subtype AS case_subtype,
    cuda.court_division_name AS court_division,
    cuda.judicial_district_name AS jurisdiction,
    c.closure_result AS case_result,
    vl.value_description AS case_result_description,
    c.closure_reason AS case_final_result,
    vl1.value_description AS case_final_description,
    c.lawsuit_amount AS case_amount,
    cuda.provisioned_amount AS provisioned_value,
    cuda.updated_cause_value_amount AS updated_case_value,
    c.cash_recovered_amount AS recovered_amount,
    c.dt_status_changed,
    c.dt_lawsuit_filed AS dt_lawsuit,
    c.dt_case_accepted AS dt_case_acceptance,
    c.dt_unrecoverable_declaration AS dt_case_completion,
    c.dt_case_assigned AS dt_agency_assignment,
    c.ts_updated
FROM
    datalake_cyber_legal_homolog_clean.case AS c
LEFT JOIN
    datalake_cyber_legal_homolog_clean.values_list vl
        ON c.closure_result = vl.value_code
LEFT JOIN
    datalake_cyber_legal_homolog_clean.values_list vl1
        ON c.closure_reason = vl1.value_code
LEFT JOIN
    datalake_cyber_legal_homolog_clean.case_uda AS cuda
        ON c.id_case = cuda.id_case
LEFT JOIN
    datalake_cyber_legal_homolog_clean.case_account AS cacct
        ON cacct.id_case = c.id_case
LEFT JOIN
    get_external_id_contract AS ct
        ON cacct.id_contract = ct.id_contract
LEFT JOIN
    get_last_delqmst_data AS dq
        ON regexp_replace(cacct.id_contract, '^([0-9])9{6}', '\1') = dq.id_contract
LEFT JOIN
    datalake_cyber_legal_homolog_clean.case_notification_log AS cntf
        ON c.id_case = cntf.id_case
        AND cacct.id_contract = cntf.id_contract
LEFT JOIN
    datalake_cyber_legal_homolog_clean.court AS crt
        ON c.id_court = crt.id_court
LEFT JOIN
    datalake_cyber_legal_homolog_clean.agency AS ag
        ON c.id_attorney_agency = ag.id_agency
