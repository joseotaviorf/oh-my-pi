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
  aud.tenant_doc_sent_count,
  aud.tenant_first_doc_sent,
  if(aud.doc_reused, aud.added_rev_doc_row, null) as tenant_auto_first_doc_sent
  aud.credit_analysis_init_date,
  aud.credit_analysis_end_date,
  aud.doc_reused,
from
  Proposta p
left join (
	select
		p_aud.id as id_aud,
		min(p_aud.dataDocumentosEnviados) as tenant_first_doc_sent,
		count(distinct p_aud.dataDocumentosEnviados) as tenant_doc_sent_count,
		max(if(p_aud.statusDocumentacaoInq = 'AnaliseCredito', from_unixtime(ure.`timestamp` / 1000), null)) as credit_analysis_init_date,
		max(if(p_aud.statusDocumentacaoInq in ('Aprovado', 'RecusadoCredito'), from_unixtime(ure.`timestamp` / 1000), null)) as credit_analysis_end_date,
		if(date_format(min(from_unixtime(ure.`timestamp` / 1000)), '%Y-%m-%d %H') != date_format(min(p_aud.dataDocumentosEnviados), '%Y-%m-%d %H'),
		   coalesce(max(ure.motivo is null or ure.motivo like '[AUTO] used previous tenant%'), 0), 0) as doc_reused,
	  min(from_unixtime(ure.`timestamp` / 1000)) as added_rev_doc_row
	from Proposta_AUD p_aud
	join UsuarioRevisionEntity ure
		on p_aud.REV = ure.id
	where p_aud.statusDocumentacaoInq_MOD = 1
		and p_aud.statusDocumentacaoInq != 'NaoEnviado'
	group by p_aud.id
) aud
	on aud.id_aud = p.id
where date(coalesce(p.criadoEm, '1900-01-01 00:00:00')) < date('{}')