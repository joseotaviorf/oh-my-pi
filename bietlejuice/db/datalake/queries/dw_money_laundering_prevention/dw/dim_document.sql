SELECT
    id_document AS sk_document,
    id_proposal AS sk_proposal,
    document_type,
    attributes,
    attachments,
    document_context
FROM
    datalake_money_laundering_prevention.document
