SELECT
    id_proposal_person AS sk_proposal_person,
    full_name,
    phone_number,
    email,
    personal_document,
    personal_document_type,
    employment_bond,
    number_of_dependents,
    current_house_situation,
    has_contributed_to_current_house,
    gender,
    marital_status,
    state_code,
    dt_birth,
    ts_created,
    ts_updated,
    NOW() AS ts_load
FROM 
    datalake_ebdb_proposal.proposal_person