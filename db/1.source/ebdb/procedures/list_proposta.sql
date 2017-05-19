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
  atualizadoEm
from 
  Proposta;
END