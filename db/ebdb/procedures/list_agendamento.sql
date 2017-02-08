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
  fupVisita
  dataFupVisita,
  criadoEm,
  atualizadoEm
from 
  Agendamento;
END