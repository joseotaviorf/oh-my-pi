SELECT
    id AS id_pre_analysis,
    idfranquia AS id_franchise,
    idparceiro AS id_partner,
    id_cliente AS id_client,
    attributedconsultant AS id_consultant,
    idpreanaliseext AS id_offer,
    idusuario AS id_registration_user,
    cpf AS client_cpf,
    `status`,
    CreatedSource AS created_source,
    priority AS priority_status,
    situacao AS situation,
    ArchiveReason AS archive_reason,
    ArchiveComplement AS archive_complement,
    vlrentrada AS down_payment_amount,
    vlrfinanciado AS financing_value,
    vlrimovel AS house_value,
    Archived AS is_archived,
    Archivedat AS ts_archived,
    TIMESTAMP(data_solicitacao) AS ts_registration
FROM
    datalake_atta_test_raw.consulta_score
