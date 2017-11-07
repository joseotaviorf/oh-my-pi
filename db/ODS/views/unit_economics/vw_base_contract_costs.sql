drop view if exists vw_base_contract_costs;
create or replace view vw_base_contract_costs as
select
  id,
  imovel_id as property_id,
  status,
  "valorAluguel" as rent_value,
  "dataRescisao" as termination_date,
  "dataFimContratoPrevisto" as expected_end_date,
  "dataAssinado" as signature_date,
  "dataEntrada" as entrance_date,
  "dataInicio" as init_date,
  "criadoEm" as created_date
from contract
  where tipo = 'FullService'
    and status in ('Finalizado', 'Ativo')
;
