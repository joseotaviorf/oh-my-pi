SELECT
    id AS id_user,
    id_usuario_cadastro AS id_user_registration,
    IDParceiro AS id_partner,
    IDFranquia AS id_franchise,
    nome AS user_name,
    sobrenome AS user_last_name,
    email AS user_email,
    status AS user_status,
    data_ultima_atualizacao AS ts_last_updated
FROM
    datalake_atta_test_raw.max_usuarios
