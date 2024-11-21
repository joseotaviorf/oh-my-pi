SELECT
    ID AS id,
    IDProposta AS id_proposal,
    STATUS AS id_current_status,
    SITant AS id_previous_proposal_situation,
    SITatu AS id_current_proposal_situation ,
    Usuario AS id_user,
    Controle AS control,
    TIMESTAMP(DtSITatu) AS ts_current_log
FROM
    datalake_atta_test_raw.log_proposta_esteira
