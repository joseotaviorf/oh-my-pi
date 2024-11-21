SELECT
    ID              AS id,
    IDProposta      AS id_proposal,
    IDUsuario       AS id_user,
    IDObsAreaEnvio  AS id_shipping_area,
    IDDocumento     AS id_document,
    CtrlProposta    AS proposal_control,
    CtrlObs         AS control_notes,
    Observacao      AS notes,
    Interna         AS is_internal,
    DtObs           AS ts_notes
FROM
    datalake_atta_test_raw.proposta_observacao
