DROP PROCEDURE IF EXISTS ebdb.list_imovel;

CREATE DEFINER = 'QuintoAndarMain'@'%'
PROCEDURE ebdb.list_imovel()
BEGIN

select -- count(1)
  i.id,
  i.aluguel,
  i.bairro,
  i.cep,
  i.cidade,
  i.complemento,
  i.condominio,
  i.dataConstrucao as data_construcao,
  i.elevador,
  i.emailContato as email_contato,
  i.emailSessaoFotos as email_sessao_fotos,
  i.endereco,
  i.estadoConservacao as estado_conservacao,
  i.fotografoPreencheDados+0 as fotografo_preenche_dados,
  i.iptu,
  i.lat,
  i.lng,
  i.mobiliado+0 as mobiliado,
  i.nivelAcabamento as nivel_acabamento,
  i.numero,
  i.numeroBanheiros as numero_banheiros,
  i.numeroQuartos as numero_quartos,
  i.numeroSuites as numero_suites,
  i.numeroVagas as numero_vagas,
  i.porcentagemCadastroCompleta as porcentagem_cadastro_completa,
  i.prefereEmailSessaoFotos+0 as prefere_email_sessao_fotos,
  i.status,
  i.telefoneContato1 as tel_contato1,
  i.telefoneContato2 as tel_contato2,
  i.telefoneSessaoFotos	as tel_sessao_fotos,
  i.tipo,
  i.tipoPorteiro as tipo_porteiro,
  i.tipoVagas as tipo_vagas,
  i.verificado+0 as verificado,
  i.usuario_id, 
  i.codigoPromocao as codigo_promocao,
  i.cotarSeguro as cotar_seguro,
  i.valorTotal as valor_total,
  i.expirationDate as expiration_date,
  i.firstPublication as first_publication,
  i.notificacaoAnuncioIncompletoProprietario as notificacao_anuncio_incompleto_proprietario,
  i.notificacaoAnuncioIncompletoAdmin as notificacao_anuncio_incompleto_admin,
  i.shortUrl as short_url,
  i.valorSeguro as valor_seguro,
  i.instrucoesAgendamento as instrucoes_agendamento,
  i.planoAceito as plano_aceito,
  i.sugerirReajusteDePreco+0 as  sugerir_reajuste_de_preco,
  i.permitePlacaAlugaSe+0 as permite_placa_aluga_se,
  i.descricaoLead as descricao_lead,
  i.prioridadeDestaqueClassificado as prioridade_destaque_classificado,
  i.corretorAmigo as corretor_amigo,
  i.porteiroAmigo as porteiro_amigo,
  i.dadosAdministradoraCondominio as  dados_administradora_condominio,
  i.referencias,
  i.condominioIncluso+0 as condominio_incluso,
  i.coordenadasManuais+0 as coordenadas_manuais,
  i.iptuIncluso+0 as iptu_incluso,
  i.followUpProprietarioSubirFotos+0 as followup_proprietario_subir_fotos,
  i.dataPrimeiroVerificado as data_primeiro_verificado,
  i.tipoColisaoLead as tipo_colisao_lead,
  i.calculoPagamentoLeadCorretor  as calculo_pagamento_lead_corretor,
  i.nomeImagemCapa as nome_imagem_capa,
  i.geoHash as geo_hash,
  i.tipoAnuncio as tipo_anuncio,
  i.infosAdmin as infos_admin,
  i.infosAdminInterna as infos_admin_interna,
  i.historicoAgendamentoFotos as historico_agendamento_fotos,
  i.calculoPagamentoLeadAfiliado as calculo_pagamento_lead_afiliado,
  i.possuiBanheiroServico+0 as possui_banheiro_servico,
  i.possuiQuartoServico+0 as possui_quarto_servico ,
  i.bairroPadrao as bairro_padrao,
  i.tipoCondominio as tipo_condominio,
  i.tipoIptu as tipo_iptu,
  i.disponivelAte as disponivel_ate,
  i.flagVerificarPrecoComparandoComMedia+0 as flag_verificar_preco_comparando_com_media,
  i.sempreconsultarproprietariovisita	 as sempre_consultar_proprietario_visita,
  i.emailPublicacaoProprietarioEnviado+0	as email_publicacao_proprietario_enviado,
  i.statusConversaoImovel	as status_conversao_imovel, 
  i.matricula	,
  i.ultimoEmailDeConfirmacaoEnviado	as ultimo_email_de_confirmacao_enviado,
  i.latlng,
  i.ultimoUpdateIndice	as ultimo_update_indice,
  i.titulo,
  i.suspensoAte	as suspenso_ate,  
  i.externalId	as external_id,
  i.emNegociacao as em_negociacao,
  i.emNegociacaoExterna	as em_negociacao_externa,
  i.entrouEmNegociacaoExterna	as entrou_em_negociacao_externa,
  i.motivoRecusaCardiff	as motivo_recusa_cardiff, 
  i.recaptadoEm	as recaptado_em,
  i.jobFotografoPendente as job_fotografo_pendente,
  i.requisitouFotosProfissionais as requisitou_fotos_profissionais,
  i.lastConfirmationAvailability	as last_confirmation_availability,
  i.cartorio,
  i.penalizationScore	as penalization_score,	
  i.receberCopiaContratoPadrao	as receber_copia_contrato_padrao,
  i.rankScore	as rank_score,
  i.ultimaPublicacao	as ultima_publicacao,
  i.confirmadoInformacoesVisita+0	  as confirmado_informacoes_visita,
  e.abreviacao as estado_abreviacao,
  e.nome as estado_nome,
--  da.tipoAfiliado as dados_afiliado_tipo_afiliado,
--  da.inicioAtuacao as dados_afiliado_inicio_atuacao,
--  da.cidadeAtuacao as dados_afiliado_cidade_atuacao,
  null as dados_afiliado_tipo_afiliado,
  null as dados_afiliado_inicio_atuacao,
  null as dados_afiliado_cidade_atuacao,
  r.cidade as regiao_cidade,
  r.macro_regiao as regiao_macro,
  r.sub_regiao as regiao_sub,
  i.regiao_id,
  c.nome as condominio_nome,
  l.nome as local_nome,
  cor.nome as corretor_nome,
  ie.WEB_CARACTERISTICAS as etapa_data_web_caracteristicas,
  ie.WEB_COPIARMAISDADOS as etapa_data_web_copiarmaisdados,
  ie.WEB_FOTOS as etapa_data_web_fotos,
  ie.WEB_UPLOADFOTOS as etapa_data_web_uploadfotos,
  ie.WEB_VALORES as etapa_data_web_valores,
  ie.MOB_DETALHES as etapa_data_mob_detalhes,
  ie.MOB_ENDERECO as etapa_data_mob_endereco,
  ie.MOB_FOTOS as etapa_data_mob_fotos,
  ie.MOB_PRECO as etapa_data_mob_preco,
  ie.MOB_TITULO as etapa_data_mob_titulo,
  ie.MOB_VISITAS as etapa_data_mob_visitas,
  ie.MOB_VISTORIA as etapa_data_mob_vistoria,
  coalesce(iv.autorizacao_de_entrada,0) as info_visita_autorizacao_de_entrada,
  coalesce(iv.proprietario_acompanha,0) as info_visita_proprietario_acompanha,
  coalesce(iv.estamos_liberados,0) as info_visita_estamos_liberados,
  coalesce(iv.prop_precisa_liberar,0) as info_visita_prop_precisa_liberar,
  coalesce(iv.chave_box_quintoandar,0) as info_visita_chave_box_quintoandar,
	
  i.dataCriacao as data_criacao,
  i.atualizadoEm as atualizado_em,
  i.usuarioQueCadastrou_id as usuario_que_cadastrou_id

from 
  Imovel i
left join
  Estado e
  on e.id = i.estado_id
-- left join
--  DadosAfiliado da
--  on da.id = i.dadosAfiliado_id
left join
  (
    select
      id as id_sub_regiao,
      `macroId` as id_macro_regiao,
      `cidadeId` as id_cidade, 
      `nome` as sub_regiao,
      `macroNome` as macro_regiao,
      `cidadeNome` as cidade
    from 
      MapRegiao
  ) r
  on i.regiao_id = coalesce(r.id_sub_regiao, r.id_macro_regiao, r.id_cidade)
left join
  Condominio c
  on c.id = i.condominioPai_id
left join
  Local l
  on l.id = i.estacaoMaisProxima_id
left join
  DadosCorretor dc
  on dc.id = i.dadosCorretor_id
left join
  Usuario cor
  on dc.usuario_id = cor.id
left join
(
  select 
    i.id as imovel_id,
    max(if(etapa='WEB_CARACTERISTICAS', data, null)) as WEB_CARACTERISTICAS,
    max(if(etapa='WEB_COPIARMAISDADOS', data, null)) as WEB_COPIARMAISDADOS,
    max(if(etapa='WEB_FOTOS', data, null)) as WEB_FOTOS,
    max(if(etapa='WEB_UPLOADFOTOS', data, null)) as WEB_UPLOADFOTOS,
    max(if(etapa='WEB_VALORES', data, null)) as WEB_VALORES,
    max(if(etapa='MOB_DETALHES', data, null)) as MOB_DETALHES,
    max(if(etapa='MOB_ENDERECO', data, null)) as MOB_ENDERECO,
    max(if(etapa='MOB_FOTOS', data, null)) as MOB_FOTOS,
    max(if(etapa='MOB_PRECO', data, null)) as MOB_PRECO,
    max(if(etapa='MOB_TITULO', data, null)) as MOB_TITULO,
    max(if(etapa='MOB_VISITAS', data, null)) as MOB_VISITAS,
    max(if(etapa='MOB_VISTORIA', data, null)) as MOB_VISTORIA
  from 
    Imovel i
  left join
    Imovel_Etapas ie
    on ie.imovel_id = i.id
  group by 
    i.id
) ie
  on ie.imovel_id = i.id
left join
(
    select
        iv.Imovel_id,
        sum(informacoesVisita='AUTORIZACAO_DE_ENTRADA') as autorizacao_de_entrada,
        sum(informacoesVisita='PROPRIETARIO_ACOMPANHA') as proprietario_acompanha,
        sum(informacoesVisita='ESTAMOS_LIBERADOS') as estamos_liberados,
        sum(informacoesVisita='PROPRIETARIO_PRECISA_LIBERAR') as prop_precisa_liberar,
        sum(informacoesVisita='CHAVE_CAIXA_QUINTOANDAR') as chave_box_quintoandar
    from
        Imovel_informacoesVisita iv
    group by iv.Imovel_id
) iv
  on iv.Imovel_id = i.id
;

end