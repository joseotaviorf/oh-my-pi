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
  p.offer_id,
  p.criadoEm,
  p.atualizadoEm,
  aud.qtdeEnviosDocumentacaoInq,
  aud.primeiroEnvioDocInq
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
;
END