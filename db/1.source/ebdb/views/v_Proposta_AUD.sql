drop view if exists v_Proposta_AUD;

create view v_Proposta_AUD as
select
  p.id as id,
  
  max(p_5a.REV) as REV_Analise5a,
  max(p_c.REV) as REV_AnaliseCardiff,
  max(p_ap.REV) as REV_Aprovado,
  
  cast(FROM_UNIXTIME(ure_5a.timestamp/ 1000) as date) as dataAnalise5a,
	cast(FROM_UNIXTIME(ure_c.timestamp/ 1000) as date) as dataAnaliseCardiff,
	cast(FROM_UNIXTIME(ure_ap.timestamp/ 1000) as date) as dataAprovado,
		
  p.dataParaMudanca as dataParaMudanca,
  p.dataProposta as dataProposta,
  p.garantia as garantia,
  p.motivacao as motivacao,
  p.propostaAluguel as propostaAluguel,
  p.status as status,
  p.imovel_id as imovel_id,
  p.proponente_id as proponente_id,
  p.explicacao as explicacao,
  p.ticketID as ticketID,
  p.descricaoGarantia as descricaoGarantia,
  p.atualizadoEm as atualizadoEm,
  p.criadoEm as criadoEm,
  p.dataAprovacao as dataAprovacao,
  p.dataDocumentosEnviados as dataDocumentosEnviados,
  p.negociacao_id as negociacao_id,
  p.dataDocumentosProprietarioEnviados as dataDocumentosProprietarioEnviados,
  p.proprietarioEnviouDocumentos as proprietarioEnviouDocumentos,
  p.inquilinoEnviouDocumentos as inquilinoEnviouDocumentos,
  p.proprietarioAceitouContrato as proprietarioAceitouContrato,
  p.inquilinoAceitouContrato as inquilinoAceitouContrato,
  p.inquilinoPastaGDrive as inquilinoPastaGDrive,
  p.proprietarioPastaGDrive as proprietarioPastaGDrive,
  p.statusDocumentacaoInq as statusDocumentacaoInq,
  p.statusDocumentacaoProp as statusDocumentacaoProp,
  p.preProposta_id as preProposta_id,
  p.fazerTermoAditivo as fazerTermoAditivo
from
  ebdb.Proposta p 
	
left join
	ebdb.Proposta_AUD p_5a 
	on p_5a.id = p.id
	and p_5a.statusDocumentacaoInq = 'Analise5a' and p_5a.statusDocumentacaoInq_MOD = 1 
left join 
	ebdb.UsuarioRevisionEntity ure_5a
	on p_5a.REV = ure_5a.id

     
left join 
	ebdb.Proposta_AUD p_c 
	on p_c.id = p.id
	and p_c.statusDocumentacaoInq = 'AnaliseCardiff' and p_c.statusDocumentacaoInq_MOD = 1 
left join 
	ebdb.UsuarioRevisionEntity ure_c
	on p_c.REV  = ure_c.id

	
left join 
	ebdb.Proposta_AUD p_ap 
	on p_ap.id = p.id
	and p_ap.statusDocumentacaoInq = 'Aprovado' and p_ap.statusDocumentacaoInq_MOD = 1	
left join 
	ebdb.UsuarioRevisionEntity ure_ap
	on p_ap.REV  = ure_ap.id
	

group by
  p.id
order by
  p.id;
