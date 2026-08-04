WITH ranked AS (
    SELECT
        CNREQID AS id_notification_request,
        CNSEQID AS id_notification_sequence,
        CNACCTG AS id_contract_group,
        CNACCT AS id_contract,
        CNCASENO AS id_case,
        CNASSLWY AS id_assigned_attorney,
        CNLWYRID AS id_supervisor_attorney,
        CNCOLLID AS id_manager,
        CNSSNUM AS client_ssn,
        CNNAME AS debtor_name,
        CNCOMM AS request_comment,
        IF(CNLFLG = 'Y', TRUE, FALSE) AS is_case_creation,
        IF(CNREQFLG = 'Y', TRUE, FALSE) AS is_request_approved,
        CNASLWDT AS dt_assigned_attorney,
        CNLCHKDT AS dt_case_creation_approved,
        CNDT AS dt_requested,
        CNREQDT AS dt_request_approved,
        CNDTUPD AS ts_updated,
        year,
        month,
        day,
        NOW() AS ts_load,
        ROW_NUMBER() OVER(PARTITION BY CNREQID, CNSEQID ORDER BY MAKE_DATE(year,month,day) DESC) AS rn
    FROM datalake_cyber_legal_raw.cantfylg
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    id_notification_request,
    id_notification_sequence,
    id_contract_group,
    id_contract,
    id_case,
    id_assigned_attorney,
    id_supervisor_attorney,
    id_manager,
    client_ssn,
    debtor_name,
    request_comment,
    is_case_creation,
    is_request_approved,
    dt_assigned_attorney,
    dt_case_creation_approved,
    dt_requested,
    dt_request_approved,
    ts_updated,
    year,
    month,
    day,
    ts_load
FROM
    ranked
WHERE
    rn = 1
