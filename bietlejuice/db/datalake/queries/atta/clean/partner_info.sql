SELECT
    id AS id_partner,
    IDUsuResp AS id_admin_user,
    IDFranquia AS id_franchise,
    idUsuCad AS id_registration_user,
    TIMESTAMP(DtCadastro) AS ts_registration,
    TIMESTAMP(DtInativo) AS ts_inactive_user,
    year,
    month,
    day
FROM
    datalake_atta_raw.parceiro
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
