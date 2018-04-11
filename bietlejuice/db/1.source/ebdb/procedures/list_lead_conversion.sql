USE ebdb;

DROP PROCEDURE IF EXISTS list_lead_conversion;
SET NAMES 'utf8';

DELIMITER $$

CREATE DEFINER = 'QuintoAndarMain'@'%'
PROCEDURE list_lead_conversion()
BEGIN

  SELECT
    id,
    imovel_id,
    leadConvertido_id,
    vendedor_id,
    gerenteContas_id,
    validado,
    status,
    tipo,
    dataConversao,
    atualizadoEm,
    criadoEm
  FROM
    ConversaoLead cl;

END
$$

DELIMITER ;