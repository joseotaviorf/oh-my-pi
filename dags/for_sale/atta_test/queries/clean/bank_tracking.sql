SELECT
    id,
    bankid AS id_bank,
    proposalId AS id_proposal,
    bankProposalId AS id_bank_proposal,
    proposalStatus AS proposal_status,
    proposalSituation AS proposal_situation,
    status AS global_status,
    itauStatusDescription AS status_description_itau,
    createdAt AS ts_created,
    updatedAt AS ts_updated
FROM
    datalake_atta_test_raw.banktracking
