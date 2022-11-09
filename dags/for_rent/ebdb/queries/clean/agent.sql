SELECT
    id,
    contratosFechados AS closed_contracts,
    creci,
    inicioAtuacao AS ts_started,
    mediaNota AS grade_average,
    estadoCreci_id AS id_creci_state,
    usuario_id AS id_user,
    descricao AS description,
    creciSupervisor AS creci_supervisor,
    shortUrl AS short_url,
    tipoCreci AS creci_type,
    verificado AS is_verified,
    indicacaoShortUrl AS indication_short_url,
    indicadoPor_id AS id_indicated_by,
    contadorPlanilhaDeLeads AS lead_sheet_counter,
    gerenteContas_id AS id_account_manager,
    ultimoCalculoComissaoIndicado AS ts_latest_referred_commission_calculation,
    tipoAfiliado AS affiliated_type
FROM
    datalake_ebdb_raw.DadosCorretor
