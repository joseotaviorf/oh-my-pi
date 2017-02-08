CREATE DEFINER = 'QuintoAndarMain'@'%'
PROCEDURE ebdb.list_preproposta()
BEGIN
select 
  id,
  aceitoAluguel,
  aceitoComprovarRenda,
  aceitoEncargos,
  aluguel,
  aluguelOriginal,
  condominioOriginal,
  iptuOriginal
  dataAprovacao,
  edicao,
  status,
  proprietarioAceitouCondicoes5A,
  criadoEm,
  atualizadoEm
from 
  PreProposta;
END