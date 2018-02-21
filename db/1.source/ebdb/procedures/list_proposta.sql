DROP PROCEDURE IF EXISTS ebdb.list_proposta;
CREATE DEFINER = 'QuintoAndarMain'@'%'
PROCEDURE ebdb.list_proposta()
BEGIN
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
  p.criadoEm,
  p.atualizadoEm,
  aud.qtdeEnviosDocumentacaoInq,
  aud.primeiroEnvioDocInq,
  aud_5a_analysis.credit_analysis_init_date
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
			min(from_unixtime(u.`timestamp`/1000)) as credit_analysis_init_date
		from Proposta_AUD p_aud
		join UsuarioRevisionEntity u
			on p_aud.REV = u.id
		where p_aud.status = 'EmAnalise'
			and p_aud.statusDocumentacaoInq = 'Aprovado'
			and p_aud.statusDocumentacaoInq_MOD = 1
		group by p_aud.id
	) aud_5a_analysis
	on aud_5a_analysis.id_aud = p.id
;
END