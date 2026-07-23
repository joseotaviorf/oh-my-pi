SELECT
    qs.id_qualification_step_progress AS sk_qualification_step_progress,
    qs.id_prospect_agent AS sk_prospect_agent,
    qs.id_qualification AS sk_qualification,
    qs.id_qualification_step AS sk_qualification_step,
    cp.id_contract_process AS sk_contract_process,
    cp.id_signature AS sk_signature,
    qs.id_user_step_responsible AS sk_user_step_responsible,
    qs.qualification_state,
    qs.qualification_state_reason,
    qs.step_name,
    qs.step_description,
    qs.step_status,
    qs.step_reason,
    qs.step_author_type,
    cp.contract_template_name,
    cp.contract_template_description,
    cp.contract_process_status,
    cp.ts_signed AS ts_contract_process_signed,
    qs.ts_step_changed,
    qs.ts_step_created,
    qs.ts_qualification_created,
    qs.ts_qualification_updated
FROM
    datalake_agent_accreditation.qualification_step AS qs
LEFT JOIN
    datalake_agent_accreditation.contract_process AS cp
        ON cp.id_prospect_agent = qs.id_prospect_agent
        AND qs.step_name = 'CONTRACT_SIGNATURE'
        AND cp.is_last_contract
