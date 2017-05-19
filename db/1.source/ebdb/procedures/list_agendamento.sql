DROP PROCEDURE IF EXISTS ebdb.list_agendamento;

CREATE DEFINER = 'QuintoAndarMain'@'%'
PROCEDURE ebdb.list_agendamento()
BEGIN
select 
  id,
  data,
  status,
  tipo,
  hash,
  confirmado,
  encerrado,
  agenteFixo,
  fupVisita,
  dataFupVisita,
  reagendadoDe_id,
  visitante_id,
  visita_id,
  imovel_id,
  agente_id,
  atendente_id,
  fluxoLocacao_id,
  criadoEm,
  atualizadoEm,
  slotDia
  
from 
  Agendamento;
END