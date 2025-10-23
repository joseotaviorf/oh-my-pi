SELECT
    CQACCTG AS id_contract_group,
    CQDOCSEQ AS id_document_sequence,
    CQDOCID AS id_document,
    CQDESC AS document_description,
    IF(CQREQFL = 'Y', TRUE, FALSE) AS is_required_flag,
    NOW() AS ts_load
FROM datalake_cyber_legal_homolog_raw.carqdoc
