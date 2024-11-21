SELECT
    ID                          AS id_pre_analysis_caixa,
    ID_USUARIO                  AS id_registration_user,
    IDParceiro                  AS id_partner,
    IDFranquia                  AS id_franchise,
    IDSolicitacao               AS id_request,
    id_segmento                 AS id_segment,
    CPF                         AS client_cpf,
    CPF2                        AS client_cpf_secondary,
    Produto                     AS product,
    UF                          AS `state`,
    TpImovel                    AS house_type,
    R_NOME                      AS r_name,
    R_SCORE                     AS r_score,
    ERRO                        AS error,
    `STATUS`                    AS pre_analysis_status,
    PRAZO                       AS deadline,
    vl_ltv                      AS ltv_value,
    vl_taxa                     AS fee_value,
    VlrImovel                   AS house_value,
    VlrEntrada                  AS down_payment_value,
    VlrFinanciado               AS financing_value,
    DATA_RETORNO                AS ts_returned,
    DATA_SOLICITACAO            AS ts_registration

FROM
    datalake_atta_test_raw.consulta_score_caixa
