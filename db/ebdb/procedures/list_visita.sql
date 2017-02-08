USE ebdb;

DROP PROCEDURE IF EXISTS list_visita;
SET NAMES 'utf8';

DELIMITER $$

CREATE DEFINER = 'QuintoAndarMain'@'%'
PROCEDURE list_visita()
BEGIN
  
  select 
    id,
    criadoEm,
    atualizadoEm,
    codigo,
    dia,
    slot,
    numeroSlots,
    tipo,
    agenteFixo,
    realEstateAgentRating_id,
    status,
    bookingType
  from 
    Visita v;

END
$$

DELIMITER ;