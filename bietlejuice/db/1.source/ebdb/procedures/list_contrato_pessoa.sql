DROP PROCEDURE IF EXISTS ebdb.list_contrato_pessoa;
CREATE DEFINER = 'QuintoAndarMain'@'%'
PROCEDURE ebdb.list_contrato_pessoa()
BEGIN
select 
  id,
  cpf,
  dataExpedicaoRG,
  dataNascimento,
  email,
  nome,
  rg,
  sexo,
  telefone,
  telefoneSecundario,
  contrato_id,
  bairro,
  cep,
  cidade,
  complemento,
  endereco,
  estadoCivil,
  numero,
  orgaoExpedidor,
  profissao,
  estado_id,
  tipo,
  nacionalidade,
  atualizadoEm,
  criadoEm,
  usuario_id,
  vaiMorar,
  legalRepresentative_cpf,
  legalRepresentative_email,
  legalRepresentative_nome,
  legalRepresentative_rg,
  withRepresentative+0 as withRepresentative
from
  ContratoPessoa
;
END