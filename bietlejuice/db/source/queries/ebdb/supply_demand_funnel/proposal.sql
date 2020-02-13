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
  aud_analysis.tenant_doc_sent_count,
  aud_analysis.tenant_first_doc_sent,
  if(aud_analysis.doc_reused, aud_analysis.added_rev_doc_row, null) as tenant_auto_first_doc_sent,
  aud_analysis.credit_analysis_first_init_date,
  aud_analysis.credit_analysis_last_init_date,
  aud_analysis.credit_analysis_first_end_date,
  aud_analysis.credit_analysis_last_end_date,
  aud_analysis.tenant_first_doc_complete_date,
  aud_analysis.tenant_last_doc_complete_date,
  coalesce(aud_analysis.doc_reused, 0) as doc_reused,
  aud_status.ts_processed,
  p.rejectionReason as rejection_reason
from
  Proposta p
left join (
	select
		p_aud.id as id_aud,
		min(p_aud.dataDocumentosEnviados) as tenant_first_doc_sent,
		count(distinct p_aud.dataDocumentosEnviados) as tenant_doc_sent_count,
    min(
      case
        when from_unixtime(ure.`timestamp` / 1000) < date('2020-01-02')
          then if(p_aud.statusDocumentacaoInq = 'AnaliseCredito', from_unixtime(ure.`timestamp` / 1000), null)
        else
          if(p_aud.statusDocumentacaoInq = 'Analise5a', from_unixtime(ure.`timestamp` / 1000), null)
      end
    ) as credit_analysis_first_init_date,
    max(
      case
        when from_unixtime(ure.`timestamp` / 1000) < date('2020-01-02')
          then if(p_aud.statusDocumentacaoInq = 'AnaliseCredito', from_unixtime(ure.`timestamp` / 1000), null)
        else
          if(p_aud.statusDocumentacaoInq = 'Analise5a', from_unixtime(ure.`timestamp` / 1000), null)
      end
    ) as credit_analysis_last_init_date,
    min(
      if(p_aud.statusDocumentacaoInq in ('Aprovado', 'RecusadoCredito', 'StandBy'), from_unixtime(ure.`timestamp` / 1000), null)
    ) as credit_analysis_first_end_date,
    max(
      if(p_aud.statusDocumentacaoInq in ('Aprovado', 'RecusadoCredito', 'StandBy'), from_unixtime(ure.`timestamp` / 1000), null)
    ) as credit_analysis_last_end_date,
    min(
      if(p_aud.statusDocumentacaoInq = 'AnaliseCredito', from_unixtime(ure.`timestamp` / 1000), null)
    ) as tenant_first_doc_complete_date,
    max(
      if(p_aud.statusDocumentacaoInq = 'AnaliseCredito', from_unixtime(ure.`timestamp` / 1000), null)
    ) as tenant_last_doc_complete_date,
		if(date_format(min(from_unixtime(ure.`timestamp` / 1000)), '%Y-%m-%d %H') != date_format(min(p_aud.dataDocumentosEnviados), '%Y-%m-%d %H'),
		     max(ure.motivo is null or ure.motivo like '[AUTO] used previous tenant%'), 0) as doc_reused,
	  min(from_unixtime(ure.`timestamp` / 1000)) as added_rev_doc_row
	from Proposta_AUD p_aud
	join UsuarioRevisionEntity ure
		on p_aud.REV = ure.id
	where p_aud.statusDocumentacaoInq_MOD = 1
		and p_aud.statusDocumentacaoInq != 'NaoEnviado'
	group by p_aud.id
) aud_analysis
	on aud_analysis.id_aud = p.id
left join (
    select
      p_aud.id as id_aud,
      max(from_unixtime(ure.`timestamp` / 1000)) as ts_processed
    from Proposta_AUD p_aud
    join UsuarioRevisionEntity ure
      on p_aud.REV = ure.id
        and p_aud.status_MOD = 1
        and p_aud.status in ('Aprovada', 'Rejeitada')
    group by 1
) aud_status
  on aud_status.id_aud = p.id
where date(coalesce(p.criadoEm, '1900-01-01 00:00:00')) <= date('{}')