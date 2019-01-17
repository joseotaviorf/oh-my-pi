drop view if exists vw_dim_bank;

create view vw_dim_bank
as
select
  id as sk_bank,
  id as id_bank,
  "atualizadoEm" as updated_at,
  "criadoEm" as created_at,
  codigo as code,
  nome as name,
  "nomeFebraban" as febraban_name,
  "featuredRank" as featured_rank,
  now() as ts_load
from bank;
