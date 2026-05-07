WITH prospect_validation AS (
    SELECT 
        pa.id_prospect_agent,
        qs.id_qualification,
        a.id_user,
        a.id_negotiation_executive_user,
        pa.uuid_person,
        pa.business_context_applied,
        a.status AS agent_status,
        qs.qualification_state,
        qs.step_name,
        qs.step_status,
        pa.ts_created
    FROM 
        datalake_agent_accreditation.prospect_agent AS pa
    LEFT JOIN
        datalake_agent_accreditation.qualification_step AS qs
            ON qs.id_prospect_agent = pa.id_prospect_agent
    LEFT JOIN
        datalake_agent_accreditation.agent AS a
            ON a.id_agent = pa.id_agent
),
union_validation_branches AS (
    SELECT 
        pv.id_prospect_agent,
        pv.id_user,
        pv.id_negotiation_executive_user,
        pv.uuid_person,
        pv.business_context_applied,
        pv.agent_status,
        pv.step_name,
        pv.step_status,
        "PENDING_VALIDATION" AS status_reason,
        pv.ts_created
    FROM 
        prospect_validation AS pv
    WHERE
        pv.qualification_state = "ON_GOING"
        AND pv.step_name = "CRECI_VALIDATION"
        AND pv.step_status = "WAITING_ACTION"
    UNION ALL
    SELECT 
        pv.id_prospect_agent,
        pv.id_user,
        pv.id_negotiation_executive_user,
        pv.uuid_person,
        pv.business_context_applied,
        pv.agent_status,
        "EN_ASSOCIATION" AS step_name,
        "WAITING_ACTION" AS step_status,
        "NOT_ATTRIBUTED" AS status_reason,
        pv.ts_created
    FROM 
        prospect_validation AS pv
    WHERE
        pv.agent_status = "ACTIVE"
        AND pv.id_negotiation_executive_user IS NULL
    UNION ALL
    SELECT 
        pv.id_prospect_agent,
        pv.id_user,
        pv.id_negotiation_executive_user,
        pv.uuid_person,
        pv.business_context_applied,
        pv.agent_status,
        spc.step_name,
        spc.step_status,
        spc.status_reason,
        pv.ts_created
    FROM 
        prospect_validation AS pv
    JOIN
        datalake_agent_accreditation.signup_profile_conflict AS spc
            ON spc.uuid_person = pv.uuid_person
    UNION ALL
    SELECT 
        pv.id_prospect_agent,
        pv.id_user,
        pv.id_negotiation_executive_user,
        pv.uuid_person,
        pv.business_context_applied,
        pv.agent_status,
        pv.step_name,
        pv.step_status,
        IF(acp.signature_status <> "AUTO_RESPONDED", CONCAT("CONTRACT_", acp.signature_status), acp.signature_status) AS status_reason,
        pv.ts_created
    FROM 
        prospect_validation AS pv
    JOIN
        datalake_agent_accreditation.contract_process AS acp
            ON acp.id_prospect_agent = pv.id_prospect_agent
            AND acp.id_qualification = pv.id_qualification
    WHERE
        pv.qualification_state = "ON_GOING"
        AND pv.step_name = "CONTRACT_SIGNATURE"
        AND acp.signature_status IN ("CANCELLED", "AUTO_RESPONDED", "DECLINED")
)
SELECT
    uv.id_prospect_agent,
    uv.id_user,
    uv.id_negotiation_executive_user,
    uv.uuid_person,
    uv.business_context_applied,
    uv.agent_status,
    uv.step_name,
    uv.step_status,
    uv.status_reason,
    uv.ts_created
FROM 
    union_validation_branches AS uv