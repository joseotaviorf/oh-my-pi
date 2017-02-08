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
  criadoEm,
  atualizadoEm
from 
  Proposta;
END