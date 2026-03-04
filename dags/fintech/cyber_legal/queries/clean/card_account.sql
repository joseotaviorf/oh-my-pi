SELECT
    CAREQID AS id_request,
    CADOCSEQ AS id_document_sequence,
    CAACCTG AS id_contract_group,
    CAACCT AS id_contract,
    CADOCID AS id_document,
    CARECCL AS id_receiving_attorney,
    CAREVCL AS id_revising_attorney,
    CADESC AS document_description,
    CACOMENT AS document_comment,
    IF(CACHEK = 'Y', TRUE, FALSE) AS is_cybercredit_review_flag,
    IF(CAREQ = 'Y', TRUE, FALSE) AS is_required_flag,
    IF(CALREVFL = 'Y', TRUE, FALSE) AS is_cyberlegal_received_flag,
    CASE
        WHEN CAREVFLG = 'Y' THEN TRUE
        WHEN CAREVFLG = 'N' THEN FALSE
        ELSE NULL
    END AS is_reviewed_approved_flag,
    CADT AS dt_cybercredit_review,
    CADTLGL AS dt_cyberlegal_receipt,
    CAREVDT AS dt_reviewed,
    NOW() AS ts_load
FROM datalake_cyber_legal_raw.cardacct
