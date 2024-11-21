SELECT
    IDSolicitacao   AS id_request,
    IDFornecedor    AS id_supplier,
    IDConsulta      AS id_check,
    IDPropostaPRD   AS id_proposal
FROM
    datalake_atta_test_raw.consulta_score_ctrl
