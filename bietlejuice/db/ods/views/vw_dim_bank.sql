drop view if exists vw_dim_bank;

create view vw_dim_bank
as
select
  id as sk_bank,
  id as id_bank,
  "atualizadoEm" as ts_updated,
  "criadoEm" as ts_created,
  codigo as code,
  nome as name,
  "nomeFebraban" as febraban_name,
  "featuredRank" as featured_rank,
  now() as ts_load
from bank;
