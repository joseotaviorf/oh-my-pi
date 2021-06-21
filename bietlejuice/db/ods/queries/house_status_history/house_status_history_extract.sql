select
	i.id, 
	i.aluguel, 
	i.andar, 
	i.andaresPredio,
	i.aptosPorAndar, 
	i.areaTotal,
	i.bairro,
	i.cep,
	i.cidade,
	i.complemento,
	i.condominio,
	i.dataConstrucao,
	nullif(i.dataParaMudar, '0000-00-00 00:00:00') as dataParaMudar, -- due to a bug in Product, 0 timestamps are being created
	i.descricaoImovel,
	i.detalhesMobilia,
	i.elevador,
	i.emailContato,
	i.emailSessaoFotos,
	i.endereco,
	i.estadoConservacao,
	i.fotografoPreencheDados,
	i.iptu,
	i.lat,
	i.lng,
	i.mobiliado,
	i.nivelAcabamento,
	i.numero,
	i.numeroBanheiros,
	i.numeroQuartos,
	i.numeroSuites,
	i.numeroVagas,
	i.porcentagemCadastroCompleta,
	i.prefereEmailSessaoFotos,
	i.status,
	i.telefoneContato1,
	i.telefoneContato2,
	i.telefoneSessaoFotos,
	i.tipo,
	i.tipoPorteiro,
	i.tipoVagas,
	i.verificado,
	i.estado_id,
	i.usuario_id,
	i.codigoPromocao,
	i.cotarSeguro,
	i.valorTotal,
	nullif(i.expirationDate, '0000-00-00 00:00:00') as expirationDate, -- due to a bug in Product, 0 timestamps are being created
	nullif(i.firstPublication, '0000-00-00 00:00:00') as firstPublication, -- due to a bug in Product, 0 timestamps are being created
	i.dadosCorretor_id,
	i.notificacaoAnuncioIncompletoProprietario,
	i.notificacaoAnuncioIncompletoAdmin,
	i.dataCriacao,
	i.shortUrl,
	i.valorSeguro,
	i.instrucoesAgendamento,
	i.planoAceito,
	i.sugerirReajusteDePreco,
	i.permitePlacaAlugaSe,
	i.descricaoLead,
	i.prioridadeDestaqueClassificado,
	i.corretorAmigo,
	i.porteiroAmigo,
	i.dadosAdministradoraCondominio,
	i.referencias,
	i.condominioIncluso,
	i.coordenadasManuais,
	i.iptuIncluso,
	i.followUpProprietarioSubirFotos,
	nullif(i.dataPrimeiroVerificado, '0000-00-00 00:00:00') as dataPrimeiroVerificado, -- due to a bug in Product, 0 timestamps are being created
	i.tipoColisaoLead,
	nullif(i.calculoPagamentoLeadCorretor, '0000-00-00 00:00:00') as calculoPagamentoLeadCorretor, -- due to a bug in Product, 0 timestamps are being created
	i.usuarioQueCadastrou_id,
	i.nomeImagemCapa,
	i.geoHash,
	i.tipoAnuncio,
	i.infosAdmin,
	i.infosAdminInterna,
	i.historicoAgendamentoFotos,
	nullif(i.calculoPagamentoLeadAfiliado, '0000-00-00 00:00:00') as calculoPagamentoLeadAfiliado, -- due to a bug in Product, 0 timestamps are being created
	i.possuiBanheiroServico,
	i.possuiQuartoServico,
	i.bairroPadrao,
	i.salesforceId,
	i.tipoCondominio,
	i.tipoIptu,
	i.disponivelAte,
	i.flagVerificarPrecoComparandoComMedia,
	i.sempreconsultarproprietariovisita,
	i.codCartografico,
	i.codConsumidorAgua,
	i.codConsumidorEnergia,
	i.codContribuinte,
	i.codigoRefIptu,
	i.emailPublicacaoProprietarioEnviado,
	i.statusConversaoImovel,
	i.matricula,
	nullif(i.ultimoEmailDeConfirmacaoEnviado, '0000-00-00 00:00:00') as ultimoEmailDeConfirmacaoEnviado, -- due to a bug in Product, 0 timestamps are being created
	i.latlng,
	nullif(i.ultimoUpdateIndice, '0000-00-00 00:00:00') as ultimoUpdateIndice, -- due to a bug in Product, 0 timestamps are being created
	i.regiao_id,
	i.titulo,
	i.atualizadoEm,
	i.condominioPai_id,
	nullif(i.suspensoAte, '0000-00-00 00:00:00') as suspensoAte, -- due to a bug in Product, 0 timestamps are being created
	i.estacaoMaisProxima_id,
	i.externalId,
	i.emNegociacao,
	i.emNegociacaoExterna,
	nullif(i.entrouEmNegociacaoExterna, '0000-00-00 00:00:00') as entrouEmNegociacaoExterna, -- due to a bug in Product, 0 timestamps are being created
	i.motivoRecusaCardiff,
	nullif(i.recaptadoEm, '0000-00-00 00:00:00') as recaptadoEm, -- due to a bug in Product, 0 timestamps are being created
	i.jobFotografoPendente,
	i.requisitouFotosProfissionais,
	i.latBkp,
	i.lngBkp,
	nullif(i.lastConfirmationAvailability, '0000-00-00 00:00:00') as lastConfirmationAvailability, -- due to a bug in Product, 0 timestamps are being created
	i.cartorio,
	i.penalizationScore,
	i.receberCopiaContratoPadrao,
	i.rankScore,
	nullif(i.ultimaPublicacao, '0000-00-00 00:00:00') as ultimaPublicacao, -- due to a bug in Product, 0 timestamps are being created
	i.confirmadoInformacoesVisita,
	i.homeownersInsuranceValue,
	i.infoPagamentoCondominio_id,
	i.suspensionReason,
	i.areaTerreno,
	i_aud.REV,
	cast(from_unixtime(ure.timestamp/1000) as date) as date_status_changed,
	case when i_aud.status = 'publicado' 
    then from_unixtime(ure_cd.timestamp/1000)
    else from_unixtime(ure_lpub_cd.timestamp/1000)
  end as datePublication,
  case when i_aud.status = 'publicado' then 1 else 0 end as published,
  from_unixtime(ure_cd.timestamp/1000) as status_time,
  date(from_unixtime(ure_cd.timestamp/1000)) as status_date,
  coalesce(i_aud_cd.status, i.status) as status_history,
  i.status as current_status,
  now() as dt_timestamp
from Imovel_AUD i_aud
join UsuarioRevisionEntity ure
	on ure.id = i_aud.REV
join Imovel i
	on i.id = i_aud.id
left join Imovel_AUD i_aud_cd
	on i_aud_cd.id = i_aud.id
		and i_aud_cd.REV = i_aud.REV
left join UsuarioRevisionEntity ure_cd
	on i_aud_cd.REV = ure_cd.id
left join Imovel_AUD i_aud_lpre_cd
	on i_aud_cd.id = i_aud_lpre_cd.id
		and i_aud_lpre_cd.REV = (select max(REV) from Imovel_AUD aux where aux.id = i_aud_cd.id and aux.REV < i_aud_cd.REV)
left join UsuarioRevisionEntity ure_lpre_cd
	on ure_lpre_cd.id = i_aud_lpre_cd.REV
left join Imovel_AUD i_aud_lpub_cd
	on i_aud_lpub_cd.id = i_aud_cd.id
		and i_aud_lpub_cd.REV = (
			select 
				max(ii_aud.REV)
			from Imovel_AUD ii_aud
			join UsuarioRevisionEntity i_ure
				on ii_aud.REV = i_ure.id
			left join Imovel_AUD ii_aud_lpre
				on ii_aud_lpre.id = ii_aud.id
			  	and ii_aud_lpre.REV = (select max(REV) from Imovel_AUD i_aux where i_aux.id = ii_aud.id and i_aux.REV < ii_aud.REV)
			where !(coalesce(ii_aud.status,'first') = coalesce(ii_aud_lpre.status,''))
				and ii_aud.status = 'publicado'
				and ii_aud.id = i_aud_cd.id
				and ii_aud.REV <= i_aud_cd.REV
	)
left join UsuarioRevisionEntity ure_lpub_cd
	on ure_lpub_cd.id = i_aud_lpub_cd.REV
where !(coalesce(i_aud_cd.status, 'first') = coalesce(i_aud_lpre_cd.status, ''))
	and cast(from_unixtime(ure.timestamp/1000) as date) >= '{}'
    and cast(from_unixtime(ure.timestamp/1000) as date) < '{}'
