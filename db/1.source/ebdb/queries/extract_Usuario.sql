CREATE PROCEDURE ebdb.list_usuario()
READS SQL DATA
BEGIN
  select
    u.id, 
    u.nome, 
    u.bairro,
    u.cep, 
    u.cidade, 
    u.complemento, 
    u.cpf,
    u.dataNascimento, 
    u.email, 
    u.emailAlternativo,
    u.endereco, 
    u.numero, 
    u.facebookId, 
    u.linkedInId,
    u.salario, 
    u.sexo, 
    u.telefonePrincipal, 
    e.abreviacao as estadoAbreviacao,
    e.nome as estadoNome,
    u.contadorlogin,
    u.naoMePergunteTelefone, 
    u.bloqueado, 
    u.rg,
    u.detalhesLeadBuscaGuiada, 
    u.recebeuBuscaGuiada, 
    da.coordinateId as dadosAgenteEmailCoordinator,
    m.nomeMunicipio as dadosAgenteCidade,
    da.cidadeAtuacao as dadosAgenteAtuacao,
    da.perfil as dadosAgentePerfil,
    da.numeroCRECI as dadosAgenteNumeroCreci,
    da.ativo as dadosAgenteAtivo,
    u.aceitaSms,
    u.preferenciaContato, 
    u.prefereContato, 
    u.dataClickAnuncie, 
    b.codigo as dadosBancarios_bancoCodigo, 
    b.nome as dadosBancarios_banco, 
    u.dadosBancarios_agencia, 
    u.dadosBancarios_contaCorrente, 
    u.dadosBancarios_cpfOuCnpj, 
    u.dadosBancarios_nome, 
    u.dadosBancarios_outroTitular, 
    u.dadosBancarios_tipoConta, 
    u.naoEnviarAvisoMensalProcura, 
    u.codAtivacaoSms, 
    u.dataGeracaoCodSms,
    u.tipoAdmin, 
    u.lastUpdateOportunidade,    
    u.salesforceAdminId, 
    u.avisadoCondicoesCardiffEm, 
    u.captadoraEnviouEmailEm, 
    u.enviadoAppECardiffEm, 
    u.googleId, 
    u.accountKitId, 
    df.inicioContrato as dadosFotogrtafoInicioContrato,
    df.tipoContrato as dadosFotogrtafoTipoContrato,  
    df.preferenciaPagamento as dadosFotogrtafoPreferenciaPagamento,
    df.ativo as dadosFotogrtafoAtivo,
    dv.inicioContrato as dadosVendedorInicioContrato,
    g.nome as dadosVendedorNomeGerente,
    daf.contadorPlanilhaDeLeads as dadosAfiliadoContadorPlanilhaDeLeads,
    daf.contratosFechados as dadosAfiliadoContratosFechados,
    daf.indicacaoShortUrl as dadosAfiliadoIndicacaoShortUrl,
    daf.inicioAtuacao as dadosAfiliadoInicioAtuacao,
    daf.ultimoCalculoComissaoIndicado as dadosAfiliadoUltimoCalculoComissaoIndicado,
    daf.verificado as dadosAfiliadoVerificado,
    daf.tipoAfiliado as dadosAfiliadoTipo,
    daf.cidadeAtuacao as dadosAfiliadoCidadeAtuacao,
    daf.principaisBairrosAtuacao as dadosAfiliadoPrincipaisBairrosAtuacao,
    daf.preferenciaPagamento as dadosAfiliadoPreferenciaPagamento,
    daf.numeroCreci as dadosAfiliadoNumeroCreci,
    daf.semanaUltimaComunicacaoBalanco as dadosAfiliadoSemanaUltimaComunicacaoBalanco,
    daf.idPlanilhaGdocs dadosAfiliadoIdPlanilhaGdocs,
    daf.ativo as dadosAfiliadoAtivo,
    gc.inicioContrato as dadosGerenteContasInicioContrato,
    ugc.nome as dadosGerenteContasNome,
    u.active,
    u.criadoEm, 
    u.atualizadoEm
  from 
    Usuario u
  left join 
    Estado e
    on e.id = u.estado_id 
  left join
    DadosAgente da
    on da.id = u.dadosAgente_id
  left join
    Municipio m
    on m.id = da.cidade_id
  left join 
    Banco b
    on b.id = u.dadosBancarios_banco_id
  left join
    DadosFotografo df
    on df.id = u.dadosFotografo_id
  left join
    DadosVendedor dv
    on dv.id = u.dadosVendedor_id
  left join
    Usuario g
    on g.id = dv.gerente_id
  left join
    DadosAfiliado daf
    on daf.id = u.dadosAfiliado_id
  left join
    DadosGerenteContas gc
    on gc.id = daf.gerenteContas_id
  left join
    Usuario ugc
    on ugc.id = gc.usuario_id;

END