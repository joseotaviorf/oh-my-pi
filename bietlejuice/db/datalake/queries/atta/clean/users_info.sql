SELECT
    id AS id_user,
    id_usuario_cadastro AS id_user_registration,
    IDParceiro AS id_partner,
    IDFranquia AS id_franchise,
    nome AS user_name,
    sobrenome AS user_last_name,
    email AS user_email,
    status AS user_status,
    data_ultima_atualizacao AS ts_last_updated,
    year,
    month,
    day
FROM
    datalake_atta_raw.max_usuarios
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
