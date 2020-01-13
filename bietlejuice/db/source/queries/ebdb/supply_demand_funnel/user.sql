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
    u.sexo,
    u.telefonePrincipal as telefone_principal,
    e.abreviacao as estado_abreviacao,
    e.nome as estado_nome,
    u.bloqueado+0 as bloqueado,
    u.rg,
    dabc.perfil as dadosagente_perfil,
    dabc.numeroCRECI as dadosagente_numero_creci,
    dabc.ativo+0 as dadosagente_ativo,
    dabc.is_sale_agent,
    dabc.is_rent_agent,
    u.aceitaSms+0 as aceita_sms,
    u.dataClickAnuncie as data_clickanuncie,
    b.codigo as dadosbancarios_banco_codigo,
    b.nome as dadosbancarios_banco,
    u.dadosBancarios_agencia as dadosbancarios_agencia,
    u.dadosBancarios_contaCorrente as dadosbancarios_conta_corrente,
    u.dadosBancarios_cpfOuCnpj as dadosbancarios_cpf_cnpj,
    u.dadosBancarios_nome as dadosbancarios_nome,
    u.dadosBancarios_outroTitular+0 as dadosbancarios_outro_titular,
    u.dadosBancarios_tipoConta as dadosbancarios_tipo_conta,
    u.tipoAdmin as tipo_admin,
    u.googleId as google_id,
    df.inicioContrato as dadosfotografo_inicio_contrato,
    df.tipoContrato as dadosfotografo_tipo_contrato,
    df.ativo+0 as dadosfotografo_ativo,
    dv.inicioContrato as dadosvendedor_inicio_contrato,
    coalesce(da2.inicioAtuacao, daf.inicioAtuacao) as dadosafiliado_inicio_atuacao,
    coalesce(daf.cidadeAtuacao, dmn.workCity) as dadosafiliado_cidade_atuacao,
    daf.preferenciaPagamento as dadosafiliado_preferencia_pagamento,
    daf.numeroCreci as dadosafiliado_numero_creci,
    daf.semanaUltimaComunicacaoBalanco as dadosafiliado_semana_ultima_comunicacao_balanco,
    daf.ativo+0 as dadosafiliado_ativo,
    u.active+0 as active,
    u.dadosAgente_id as dados_agente_id,
    u.dadosFotografo_id as dados_fotografo_id,
    u.dadosVendedor_id as dados_vendedor_id,
    u.dadosAfiliado_id as dados_afiliado_id,
    (daf.doormanAffiliateData_id is not null) as flg_doorman_affiliate,
    dmn.joinedProgramAt as dt_doorman_joined,
    u_c.tem_imovel,
    u_c.tem_app_inquilino,
    u_c.tem_contrato_ativo,
    u_c.inquilino,
    p.first_dt_document_sent,
    p.last_dt_document_sent,
    i.first_dt_sent_to_insurance,
    u.criadoEm as criado_em,
    u.atualizadoEm as atualizado_em,
    u.contaCorrente_id
  from
    Usuario u
  left join
    Estado e
    on e.id = u.estado_id
  left join (
    select
        _da.id as dadosagente_id,
        _da.numeroCRECI,
        _da.perfil,
        _da.ativo,
        _da.cidade_id,
        max(cast(_dabc.businessContextsServed = 'SALE' as unsigned)) as is_sale_agent,
        -- non existent agents on businessContextsServed table are assumed as RENT
        max(cast(coalesce(_dabc.businessContextsServed, 'RENT') = 'RENT' as unsigned))
            as is_rent_agent
    from DadosAgente as _da
    left join DadosAgente_businessContextsServed _dabc
        on _dabc.DadosAgente_id = _da.id
    group by 1,2,3,4,5
  ) dabc
    on dabc.dadosagente_id = u.dadosAgente_id
  left join
    Municipio m
    on m.id = dabc.cidade_id
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
    DoormanAffiliateData dmn
    on dmn.id = daf.doormanAffiliateData_id
  left join
	(select id, min(REV) as REV from DadosAfiliado_AUD where inicioAtuacao is not null group by id) da1
	on da1.id = u.dadosAfiliado_id
  left join
    DadosAfiliado_AUD da2
    on da1.id = da2.id and da1.REV = da2.REV
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
      statusDocumentacaoInq = 'AnaliseCredito'
    group BY
      1
  ) i
  on i.proponente_id = u.id
where DATE(coalesce(u.criadoEm, '1900-01-01 00:00:00')) <= DATE('{}')