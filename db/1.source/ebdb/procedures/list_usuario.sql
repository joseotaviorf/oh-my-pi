DROP PROCEDURE IF EXISTS ebdb.list_usuario;

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
    u.dataNascimento as data_nascimento, 
    u.email, 
    u.emailAlternativo as email_alternativo,
    u.endereco, 
    u.numero, 
    u.facebookId as facebook_id, 
    u.linkedInId as linkedin_id,
    u.salario, 
    u.sexo, 
    u.telefonePrincipal as telefone_principal, 
    e.abreviacao as estado_abreviacao,
    e.nome as estado_nome,
    u.contadorlogin,
    u.naoMePergunteTelefone+0 as nao_me_prgunte_telefone, 
    u.bloqueado+0 as bloqueado, 
    u.rg,
    u.detalhesLeadBuscaGuiada as detalhes_lead_busca_guiada, 
    u.recebeuBuscaGuiada+0 as recebeu_busca_guiada, 
    da.coordinateId as dadosagente_email_coordinator ,
    m.nomeMunicipio as dadosagente_cidade,
    da.cidadeAtuacao as dadosagente_atuacao,
    da.perfil as dadosagente_perfil,
    da.numeroCRECI as dadosagente_numero_creci,
    da.ativo+0 as dadosagente_ativo,
    u.aceitaSms+0 as aceita_sms,
    u.preferenciaContato as preferencia_contato, 
    u.prefereContato as prefere_contato, 
    u.dataClickAnuncie as data_clickanuncie, 
    b.codigo as dadosbancarios_banco_codigo, 
    b.nome as dadosbancarios_banco, 
    u.dadosBancarios_agencia as dadosbancarios_agencia, 
    u.dadosBancarios_contaCorrente as dadosbancarios_conta_corrente, 
    u.dadosBancarios_cpfOuCnpj as dadosbancarios_cpf_cnpj, 
    u.dadosBancarios_nome as dadosbancarios_nome, 
    u.dadosBancarios_outroTitular+0 as dadosbancarios_outro_titular, 
    u.dadosBancarios_tipoConta as dadosbancarios_tipo_conta, 
    u.naoEnviarAvisoMensalProcura+0 as nao_enviar_aviso_mensal_procura, 
    u.codAtivacaoSms as cod_ativacao_sms, 
    u.dataGeracaoCodSms as data_geracao_cod_sms,
    u.tipoAdmin as tipo_admin, 
    u.lastUpdateOportunidade as last_update_oportunidade,
    u.avisadoCondicoesCardiffEm as data_avisado_condicoes_cardiff, 
    u.captadoraEnviouEmailEm as data_captadora_enviou_email, 
    u.enviadoAppECardiffEm as data_enviado_app_e_cardiff, 
    u.googleId as google_id, 
    u.accountKitId as account_kit_id, 
    df.inicioContrato as dadosfotografo_inicio_contrato,
    df.tipoContrato as dadosfotografo_tipo_contrato,  
    df.preferenciaPagamento as dadosfotografo_preferencia_pagamento,
    df.ativo+0 as dadosfotografo_ativo,
    dv.inicioContrato as dadosvendedor_inicio_contrato,
    g.nome as dadosvendedor_nome_gerente,
    daf.contadorPlanilhaDeLeads as dadosafiliado_contador_planilha_leads,
    daf.contratosFechados as dadosafiliado_contratos_fechados,
    daf.indicacaoShortUrl as dadosafiliado_indicacao_shorturl,
    coalesce(da2.initioAtuacao, daf.inicioAtuacao) as dadosafiliado_inicio_atuacao,
    daf.ultimoCalculoComissaoIndicado as dadosafiliado_ultim_calculo_comissao_indicado,
    daf.verificado+0 as dadosafiliado_verificado,
    daf.tipoAfiliado as dadosafiliado_tipo,
    daf.cidadeAtuacao as dadosafiliado_cidade_atuacao,
    daf.principaisBairrosAtuacao as dadosafiliado_principais_bairros_atuacao,
    daf.preferenciaPagamento as dadosafiliado_preferencia_pagamento,
    daf.numeroCreci as dadosafiliado_numero_creci,
    daf.semanaUltimaComunicacaoBalanco as dadosafiliado_semana_ultima_comunicacao_balanco,
    daf.idPlanilhaGdocs dadosafiliado_id_planilha_gdocs,
    daf.ativo+0 as dadosafiliado_ativo,
    gc.inicioContrato as dadosgerentecontas_inicio_contrato,
    ugc.nome as dadosgerentecontas_nome,
    u.active+0 as active,

    u.dadosAgente_id as dados_agente_id,
    u.dadosFotografo_id as dados_fotografo_id,
    u.dadosVendedor_id as dados_vendedor_id,
    u.dadosAfiliado_id as dados_afiliado_id,
    u_c.tem_imovel,
    u_c.tem_app_inquilino,
    u_c.tem_contrato_ativo,
    u_c.inquilino,

    p.first_dt_document_sent,
    p.last_dt_document_sent,
    i.first_dt_sent_to_insurance,


    u.criadoEm as criado_em, 
    u.atualizadoEm as atualizado_em
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
	(select id, min(REV) as REV from DadosAfiliado_AUD where inicioAtuacao is not null group by id) da1
	on da1.id = u.dadosAfiliado_id
  left join
    DadosAfiliado_AUD da2
    on da1.id = da2.id and da1.REV = da2.REV
  left join
    DadosGerenteContas gc
    on gc.id = daf.gerenteContas_id
  left join
    Usuario ugc
    on ugc.id = gc.usuario_id


  left join
  (
    select
      U.id,
      I.isProp as tem_imovel,
      D.usuario_id is not null as tem_app_inquilino,
      C.usuario_id is not null as tem_contrato_ativo,
      
      (
        U.dadosAfiliado_id is null 
        and U.dadosFotografo_id is null 
        and U.dadosVendedor_id is null 
        and U.dadosAgente_id is null 
        and not I.isProp
      ) or  C.usuario_id is not null as inquilino
    
    from
     Usuario U

    left join
     Agendamento a
      on a.visitante_id = U.id
    
    left join
     (
       select
         I.usuario_id,
         count(I.usuario_id)>0 as isProp
       from
         Imovel I    
       group by
         I.usuario_id
     ) I
     on U.id = I.usuario_id
    
    left join
     (
       select distinct
         d.usuario_id
       from
         Device d
       where
         d.mobileApp = 'Inquilinos'
     ) D
     on U.id = D.usuario_id
    
    left join
     (
       select distinct
         usuario_id
       from
         Contrato
     ) C
     on U.id = C.usuario_id
    
    group by
      U.id,
      I.usuario_id is not null,
      D.usuario_id is not null,
      C.usuario_id is not null
  ) u_c
  on u_c.id = u.id

  left join
  (
    select 
      p.proponente_id,
      min(p.dataDocumentosEnviados) as first_dt_document_sent,
      max(p.dataDocumentosEnviados) as last_dt_document_sent
    from 
      Proposta p
    where 
      dataDocumentosEnviados is not null
    group by
      p.proponente_id
  ) p
  on p.proponente_id = u.id

  left join
  (    
    select 
      proponente_id,
      FROM_UNIXTIME(min(r.timestamp)/1000) as first_dt_sent_to_insurance
    from 
      Proposta_AUD p
    left JOIN
      UsuarioRevisionEntity r
      on r.id = p.REV
    where 
      statusDocumentacaoInq = 'AnaliseCardiff'
    group BY
      1
  ) i
  on i.proponente_id = u.id
;

END