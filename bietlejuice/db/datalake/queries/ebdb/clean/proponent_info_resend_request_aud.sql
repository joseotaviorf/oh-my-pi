SELECT
    id,
    proposalProponentId AS id_proponent_proposal,
    proposalDocumentId AS id_proposal_document,
    REV AS rev,
    REVTYPE AS rev_type,
    proponentInfoType AS proponent_info_type,
    resendDocumentReason AS resend_document_reason,
    description,
    proponentInfoType_MOD AS mod_proponent_info_type,
    resendDocumentReason_MOD AS mod_resend_document_reason
FROM 
    datalake_ebdb_raw.proponentinforesendrequest_aud