select
  p.id,
  p.dataParaMudanca,
  p.dataProposta,
  p.garantia,
  p.motivacao,
  p.propostaAluguel,
  p.status,
  p.dataAprovacao,
  p.inquilinoEnviouDocumentos,
  p.dataDocumentosEnviados,
  p.proprietarioEnviouDocumentos,
  p.dataDocumentosProprietarioEnviados,
  p.inquilinoAceitouContrato,
  p.proprietarioAceitouContrato,
  p.statusDocumentacaoInq,
  p.statusDocumentacaoProp,
  p.fazerTermoAditivo,
  p.preProposta_id,
  p.offer_id,
  p.criadoEm,
  p.atualizadoEm,
  aud.qtdeEnviosDocumentacaoInq,
  aud.primeiroEnvioDocInq,
  aud_5a_analysis_init.credit_analysis_init_date,
  aud_5a_analysis_end.credit_analysis_end_date
from
  Proposta p
join (
		select
			id as id_aud,
			min(dataDocumentosEnviados) as primeiroEnvioDocInq,
			count(distinct dataDocumentosEnviados) as qtdeEnviosDocumentacaoInq
		from Proposta_AUD
		group by id
	) aud
	on aud.id_aud = p.id
left join (
		select
			p_aud.id as id_aud,
			max(from_unixtime(u.`timestamp`/1000)) as credit_analysis_init_date
		from Proposta_AUD p_aud
		join UsuarioRevisionEntity u
			on p_aud.REV = u.id
		where p_aud.statusDocumentacaoInq = 'AnaliseCredito'
			and p_aud.statusDocumentacaoInq_MOD = 1
		group by p_aud.id
	) aud_5a_analysis_init
	on aud_5a_analysis_init.id_aud = p.id
left join (
		select
			p_aud.id as id_aud,
			max(from_unixtime(u.`timestamp`/1000)) as credit_analysis_end_date
		from Proposta_AUD p_aud
		join UsuarioRevisionEntity u
			on p_aud.REV = u.id
		where p_aud.statusDocumentacaoInq in ('Aprovado', 'RecusadoCredito')
			and p_aud.statusDocumentacaoInq_MOD = 1
		group by p_aud.id
	) aud_5a_analysis_end
	on aud_5a_analysis_end.id_aud = p.id
where coalesce(p.criadoEm, '1900-01-01 00:00:00') < '{}'