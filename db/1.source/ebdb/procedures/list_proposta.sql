DROP PROCEDURE IF EXISTS ebdb.list_proposta;
CREATE DEFINER = 'QuintoAndarMain'@'%'
PROCEDURE ebdb.list_proposta()
BEGIN
select 
  id,
  dataParaMudanca, 
  dataProposta,
  garantia,
  motivacao,
  propostaAluguel,
  status,
  ticketID,
  dataAprovacao,
  inquilinoEnviouDocumentos,
  dataDocumentosEnviados,
  proprietarioEnviouDocumentos,
  dataDocumentosProprietarioEnviados,
  inquilinoAceitouContrato,
  proprietarioAceitouContrato,
  statusDocumentacaoInq,
  statusDocumentacaoProp,
  fazerTermoAditivo, 
  preProposta_id, 
  criadoEm,
  atualizadoEm,
  qtdeEnviosDocumentacaoInq
from 
  Proposta p
join
	(
		select
			id as id_aud,
			count(distinct dataDocumentosEnviados) as qtdeEnviosDocumentacaoInq
		from
			Proposta_AUD
		group by
			id
	) aud
	on aud.id_aud = p.id
;
END