SELECT
    id,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created,
    cliente_id AS id_client,
    gerente_id AS id_manager,
    imovel_id AS id_house,
    ignorarAntesDe as ts_ignore_before,
    status,
    etapaRejeitada AS is_step_rejected,
    withoutIptu AS has_no_iptu,
    currentOffer_id AS id_current_offer,
    currentContrato_id AS id_current_contract,
    currentProposta_id AS id_current_proposal,
    originalRentFlowId AS id_original_rent_flow
FROM
    datalake_ebdb_raw.fluxolocacao
