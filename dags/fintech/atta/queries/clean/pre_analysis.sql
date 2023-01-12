SELECT
    id                          AS id_pre_analysis,
    idfranquia                  AS id_franchise,
    idparceiro                  AS id_partner,
    idpreanaliseext             AS id_offer,
    idusuario                   AS id_registration_user,
    cpf                         AS client_cpf,
    `status`,
    priority                    AS priority_status,
    situacao                    AS situation,
    vlrentrada                  AS down_payment_amount,
    vlrfinanciado               AS financing_value,
    vlrimovel                   AS house_value,
    TIMESTAMP(data_solicitacao) AS ts_registration
FROM
    datalake_atta_raw.consulta_score
