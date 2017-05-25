DROP PROCEDURE IF EXISTS ebdb.list_contrato;
CREATE DEFINER = 'QuintoAndarMain'@'%'
PROCEDURE ebdb.list_contrato()
BEGIN
select 
  id,
  emailFatura,
  valorAluguel,
  numImovel,
  diaMesCobranca,
  garantia,
  tipo,
  status,
  dataCalculoComissaoAfiliado,
  dataCalculoComissaoCorretor,
  dataInicio,
  dataAssinado,
  dataMinutaAprovada,
  dataEntrada,
  dataFimContratoPrevisto,
  dataRescisao,
  nomeBanco,
  paganteCondominio,
  paganteIptu,
  responsavelCondominio,
  responsavelIptu,
  seguroFianca_parcelas,
  seguroFianca_valor,
  seguroResidencial_parcelas,
  seguroResidencial_valor,
  taxaComissaoPrimeiroAluguel,
  valorCondominio,
  valorIptu,
  tipoAssinatura,
  dataContratoEletronicoEnviado,
  statusClosing,
  contratoAssinado,
  googleDriveId,
  tokenESignatureLocacao,
  tokenESignatureAdm,
  contratoAdministracaoAssinado,
  contratoAutorizacaoEntradaAssinado,
  contratoLocacaoAssinado,
  dataTrocaTitularidade,
  proposta_id,
  imovel_id,
  criadoEm,
  atualizadoEm 
from 
  Contrato
where id != 4055; -- esse contrato tem varios cobrancas de TaxaCorretagem, entao decidimos por enquanto em nao trazer ele para o DW

END