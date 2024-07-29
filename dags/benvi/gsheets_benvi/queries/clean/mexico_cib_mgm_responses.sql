SELECT
    CAST(id_del_cib_que_indico AS BIGINT) AS id_cib_that_referred,
    CAST(id_del_cib_referido AS BIGINT) AS id_cib_referred,
    nombre_del_cib_que_indico AS name_cib_that_referred,
    nombre_del_cib_referido AS name_cib_referred,
    hunter AS name_hunter,
    TO_TIMESTAMP(timestamp, 'M/dd/yyyy HH:mm:ss') AS ts_registered
FROM
    datalake_gsheets_raw.member_get_member_cib_responses
