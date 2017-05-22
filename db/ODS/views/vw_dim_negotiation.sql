drop view if exists vw_dim_negotiation;
create view vw_dim_negotiation
as
SELECT
  id as sk_contract,
  id as id_contract,
  "deadlineEm" as dt_deadline,
  "enviadaEm" as dt_send,
  garantia as guarantee,
  periodo as period,
  "propostaAluguel" as renting_proposal_value,
  fase as step,
  status,
  "rejeitadaEm" as dt_rejection,
  "motivoRejeicao" as rejection_reason,
  "criadoEm" as dt_created,
  "atualizadoEm" as dt_updated,
  now()::timestamp as dt_timestamp
FROM
  public.negotiation ;

