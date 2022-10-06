SELECT
    id AS id_pre_analysis,
    idfranquia AS id_franchise,
    idparceiro AS id_partner,
    idpreanaliseext AS id_offer,
    idusuario AS id_registration_user,
    cpf AS client_cpf,
    vlrentrada AS down_payment_amount,
    vlrfinanciado AS financing_value,
    vlrimovel AS house_value,
    TIMESTAMP(data_solicitacao) AS ts_registration,
    year,
    month,
    day
FROM
    datalake_atta_raw.consulta_score
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
