SELECT
    id AS id_partner,
    IDUsuResp AS id_admin_user,
    IDFranquia AS id_franchise,
    idUsuCad AS id_registration_user,
    nome AS partner_name,
    TIMESTAMP(DtCadastro) AS ts_registration,
    TIMESTAMP(DtInativo) AS ts_inactive_user
FROM
    datalake_atta_test_raw.parceiro
