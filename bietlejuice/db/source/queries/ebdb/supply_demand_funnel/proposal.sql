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
  -- Dates related to document sent
  aud_analysis.tenant_doc_sent_count,
  aud_analysis.tenant_first_doc_sent,
  if(aud_analysis.doc_reused, aud_analysis.added_rev_doc_row, null) as tenant_auto_first_doc_sent,
  -- Dates related to credit analysis (these dates had their business rules changed on jan/2020 and are deprecated
  -- after 08/06/2020).
  aud_analysis.credit_analysis_first_init_date,
  aud_analysis.credit_analysis_last_init_date,
  aud_analysis.credit_analysis_first_end_date,
  aud_analysis.credit_analysis_last_end_date,
  aud_analysis.credit_approved_last_date,
  -- Dates related to document completed (not sure if these dates
  aud_analysis.tenant_first_doc_complete_date,
  aud_analysis.tenant_last_doc_complete_date,
  coalesce(aud_analysis.doc_reused, 0) as doc_reused,
  aud_status.ts_processed,
  p.rejectionReason as rejection_reason,
  -- New dates related to credit evaluation
  aud_analysis.credit_evaluation_first_init_date,
  aud_analysis.credit_evaluation_last_init_date,
  aud_analysis.credit_evaluation_negative_first_date,
  aud_analysis.credit_evaluation_negative_last_date,
  aud_analysis.doc_analysis_first_approved_date,
  aud_analysis.doc_analysis_last_approved_date,
  aud_analysis.doc_analysis_first_rejected_date,
  aud_analysis.doc_analysis_last_rejected_date
from
  Proposta p
left join (
	select
		p_aud.id as id_aud,
	-- It remains the same, and this result should be the same as the first date when statusDocumentacaoInq = 'Analise5a'
		min(p_aud.dataDocumentosEnviados) as tenant_first_doc_sent,
		count(distinct p_aud.dataDocumentosEnviados) as tenant_doc_sent_count,
	-- All columns related to credit analysis should be considered deprecated after 2020-08-06
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
    max(
      if(p_aud.statusDocumentacaoInq = 'Aprovado', from_unixtime(ure.`timestamp` / 1000), null)
    ) as credit_approved_last_date,
    -- Columns related to doc completed also can be considered deprecated
    min(
      if(p_aud.statusDocumentacaoInq = 'AnaliseCredito', from_unixtime(ure.`timestamp` / 1000), null)
    ) as tenant_first_doc_complete_date,
    max(
      if(p_aud.statusDocumentacaoInq = 'AnaliseCredito', from_unixtime(ure.`timestamp` / 1000), null)
    ) as tenant_last_doc_complete_date,
    coalesce(isTenantAutomaticSubmission, false) as doc_reused,
	min(from_unixtime(ure.`timestamp` / 1000)) as added_rev_doc_row,
    -- New column to consider credit evaluation step
    -- New column to consider credit evaluation started
    min(
      case
        when from_unixtime(ure.`timestamp` / 1000) > date('2020-06-07')
          then if(p_aud.statusDocumentacaoInq = 'AnaliseCredito', from_unixtime(ure.`timestamp` / 1000), null)
        else
          null
      end
    ) as credit_evaluation_first_init_date,
    max(
      case
        when from_unixtime(ure.`timestamp` / 1000) > date('2020-06-07')
          then if(p_aud.statusDocumentacaoInq = 'AnaliseCredito', from_unixtime(ure.`timestamp` / 1000), null)
        else
          null
      end
    ) as credit_evaluation_last_init_date,
    -- New column to consider credit evaluation ended as negative
    min(
      case
        when from_unixtime(ure.`timestamp` / 1000) > date('2020-06-07')
          then if(p_aud.statusDocumentacaoInq = 'RecusadoCredito' and rejectionReason = 'CreditEvaluationRejected', from_unixtime(ure.`timestamp` / 1000), null)
        else
          null
      end
    ) as credit_evaluation_negative_first_date,
    max(
      case
        when from_unixtime(ure.`timestamp` / 1000) > date('2020-06-07')
          then if(p_aud.statusDocumentacaoInq = 'RecusadoCredito' and rejectionReason = 'CreditEvaluationRejected', from_unixtime(ure.`timestamp` / 1000), null)
        else
          null
      end
    ) as credit_evaluation_negative_last_date,
    -- For the new flow it's important to know when the doc analysis ended and was approved/rejected
    min(
     case
        when from_unixtime(ure.`timestamp` / 1000) > date('2020-06-07')
      then if(p_aud.statusDocumentacaoInq = 'Aprovado', from_unixtime(ure.`timestamp` / 1000), null)
      else
          null
      end
    ) as doc_analysis_first_approved_date,
    max(
     case
        when from_unixtime(ure.`timestamp` / 1000) > date('2020-06-07')
      then if(p_aud.statusDocumentacaoInq = 'Aprovado', from_unixtime(ure.`timestamp` / 1000), null)
      else
          null
      end
    ) as doc_analysis_last_approved_date,
    min(
     case
        when from_unixtime(ure.`timestamp` / 1000) > date('2020-06-07')
      then if(p_aud.statusDocumentacaoInq = 'RecusadoCredito' and rejectionReason = 'TenantDocumentationRejected', from_unixtime(ure.`timestamp` / 1000), null)
      else
          null
      end
    ) as doc_analysis_first_rejected_date,
    max(
     case
        when from_unixtime(ure.`timestamp` / 1000) > date('2020-06-07')
      then if(p_aud.statusDocumentacaoInq = 'RecusadoCredito' and rejectionReason = 'TenantDocumentationRejected', from_unixtime(ure.`timestamp` / 1000), null)
      else
          null
      end
    ) as doc_analysis_last_rejected_date
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
