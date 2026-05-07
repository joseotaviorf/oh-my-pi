SELECT
    q.id_agent_prospect AS id_prospect_agent,
    acp.id_qualification,
    acp.id AS id_contract_process,
    acp.id_contract_template,
    acp.id_replaced_process,
    ad.id AS id_agreement_document,
    s.id AS id_signature,
    IF(acp.author_type = "PERSON", acp.author_identifier, NULL) AS uuid_author_person,
    act.business_association,
    acp.status AS contract_process_status,
    s.status AS signature_status,
    acp.ts_initiated,
    acp.ts_finished,
    acp.ts_created,
    acp.ts_updated  
FROM
    datalake_ebdb_clean.accreditation_contract_process AS acp
JOIN
    datalake_ebdb_clean.accreditation_contract_template AS act
        ON act.id = acp.id_contract_template
JOIN
    datalake_ebdb_clean.qualification AS q
        ON q.id = acp.id_qualification
JOIN 
    datalake_signatures_clean.agreement_document AS ad
        ON acp.uuid_contract_process = ad.id_internal_reference
JOIN 
    datalake_signatures_clean.signature AS s
        ON ad.id = s.id_agreement_document
WHERE
    ad.internal_reference_name = 'QUINTOANDAR_AGENT'
    AND ad.type = 'QUINTOANDAR_PARTNERSHIP_CONTRACT'