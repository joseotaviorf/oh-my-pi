drop view if exists vw_dim_pre_proposal;
create view vw_dim_pre_proposal
as
SELECT
  id as sk_pre_proposal,
  id as id_pre_proposal,
  aluguel as renting_value,
  "aluguelOriginal" as renting_original_value,
  "condominioOriginal" as condo_original_value,
  "dataAprovacao" as dt_approved,
  edicao as editing,
  status,
  "proprietarioAceitouCondicoes5A" as owner_accepted_5A_conditions,
  usuario_id,
  imovel_id,
  "criadoEm" as dt_created,
  "atualizadoEm" as dt_updated,
  now()::timestamp as dt_timestamp,
  "ultimoUpdateEdicao" > 0 as offer_submitted,
  "ultimoUpdateEdicao" as ultimo_update_edicao,
  "dataPrimerioEnvio" as dt_first_sent
FROM
  public.pre_proposal;

--select * from vw_dim_pre_proposal
