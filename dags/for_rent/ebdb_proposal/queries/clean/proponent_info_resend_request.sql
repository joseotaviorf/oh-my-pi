SELECT
    id,
    proposalProponentId AS id_proponent_proposal,
    proposalDocumentId AS id_proposal_document,
    proponentInfoType AS proponent_info_type,
    resendDocumentReason AS resend_document_reason,
    description,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM 
    datalake_ebdb_raw.proponentinforesendrequest