SELECT
    id AS id_airtable_record,
    CAST(id AS BIGINT) AS id_historical,
    CAST(id_admin AS BIGINT) AS id_admin,
    ativados_rental AS id_rental_activated,
    CAST(creci AS BIGINT) AS agent_creci,
    email AS agent_email,
    telefone_principal AS agent_main_phone_number,
    name AS agent_name,
    cpf,
    modalidade AS model_type,
    status,
    regiao AS region,
    TO_DATE(data_ativacao, 'yyyy-MM-dd') AS dt_activated,
    TO_DATE(_envio_de_contrato, 'yyyy-MM-dd') AS dt_contract_sent,
    TO_DATE(assinatura_do_contrato, 'yyyy-MM-dd') AS dt_contract_signed,
    TO_DATE(semana_de_credenciamento, 'yyyy-MM-dd') AS dt_week_accreditated,
    TO_TIMESTAMP(last_modified) AS ts_updated,
    TIMESTAMP(createdTime) AS ts_airtable_record_created,
    year,
    month,
    day
FROM
    datalake_airtable_test_raw.historical
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}