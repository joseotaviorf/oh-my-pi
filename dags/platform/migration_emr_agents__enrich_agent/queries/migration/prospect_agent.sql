WITH last_contract AS (
    SELECT
        id_prospect_agent,
        contract_template_name,
        contract_process_status,
        signature_status AS contract_signature_status,
        ts_initiated AS ts_contract_process_initiated,
        ts_signed AS ts_contract_signed,
        ts_finished AS ts_contract_process_finished
    FROM
        datalake_agent_accreditation.contract_process
    WHERE
        is_last_contract
),
qualification_by_agent AS (
    SELECT
        id_prospect_agent,
        id_qualification,
        qualification_state,
        MAX(step_status) FILTER(WHERE step_name = 'CRECI_VALIDATION') AS creci_validation_status,
        MAX(ts_step_changed) FILTER(WHERE step_name = 'CRECI_VALIDATION' AND step_status = 'APPROVED') AS ts_creci_validation_approved
    FROM
        datalake_agent_accreditation.qualification_step
    GROUP BY 1,2,3
)
SELECT
    pa.id AS id_prospect_agent,
    a.id AS id_agent,
    qba.id_qualification,
    IF(qapa.primary_operating_region_type = 'HUB', qapa.id_primary_operating_region, NULL) AS id_business_unit,
    IF(qapa.parent_operating_region_type = 'REGION', qapa.id_parent_operating_region, NULL) AS id_region,
    pa.uuid_prospect,
    pa.uuid_person,
    pa.legal_entity_type,
    pa.status,
    qba.qualification_state,
    qba.creci_validation_status,
    lc.contract_signature_status,
    lc.contract_template_name,
    pa.business_association,
    qapa.business_context_of_interest AS business_context_applied,
    pa.quintoandar_knowledge,
    pa.social,
    qapa.creci,
    qapa.creci_uf,
    qapa.commuting_method,
    qapa.referral_code,
    qapa.maximum_acquisition_per_month,
    qapa.minimum_acquisition_per_month,
    qapa.maximum_available_days,
    qapa.minimum_available_days,
    qapa.maximum_years_of_experience AS years_of_experience,
    qapa.is_available_on_weekends,
    qapa.is_accepted_alternative_context,
    qapa.is_accepted_alternative_region,
    IF(pa.status = 'CONVERTED', ROW_NUMBER() OVER(PARTITION BY pa.uuid_person ORDER BY pa.ts_created DESC) = 1, FALSE) AS is_last_prospect_person_converted,
    qba.ts_creci_validation_approved,
    lc.ts_contract_process_initiated,
    lc.ts_contract_signed,
    lc.ts_contract_process_finished,
    pa.ts_created,
    pa.ts_updated
FROM
    datalake_ebdb_clean.prospect_agent AS pa
LEFT JOIN
    datalake_ebdb_clean.agent AS a
        ON a.uuid_person = pa.uuid_person
LEFT JOIN
    datalake_ebdb_clean.quintoandar_prospect_agent AS qapa
        ON qapa.id_prospect_agent = pa.id
LEFT JOIN
    qualification_by_agent AS qba
        ON qba.id_prospect_agent = pa.id
LEFT JOIN
    last_contract AS lc
        ON lc.id_prospect_agent = pa.id
