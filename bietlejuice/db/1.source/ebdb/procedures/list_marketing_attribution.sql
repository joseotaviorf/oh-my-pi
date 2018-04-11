DROP PROCEDURE IF EXISTS ebdb.list_marketing_attribution;

CREATE DEFINER = 'QuintoAndarMain'@'%'
PROCEDURE ebdb.list_marketing_attribution()
BEGIN

select  
  id,
  uuid,
  tipo,
  imovel_id,
  usuario_id,
  campaign,
  channel,
  eventType as event_type,
  mobileApp as mobile_app,
  platform,
  subchannel,
  adquiridoEm as adquirido_em,
  criadoEm as criado_em,
  atualizadoEm as atualizado_em
from 
  v_Aquisicao
;
END