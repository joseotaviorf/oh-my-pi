select
    id as sk_proposal_person,
    name as full_name,
    phone_number,
    email,
    cpf as id_personal_document,
    case when cpf rlike '([0-9]{3})(.)([0-9]{3})(.)([0-9]{3})(-)([0-9]{2})' then 'CPF'
		  when cpf rlike '([0-9]{2})(.)([0-9]{3})(.)([0-9]{3})(\/)([0-9]{4})(-)([0-9]{2})' then 'CNPJ' 
		else null end as personal_document_type,
    case when emp_link = 'CLT' then 'CLT'
      when emp_link = 'Empresario' then 'businessman'
      when emp_link = 'FuncionarioPublico' then 'government employee'
      when emp_link = 'ProfissionalLiberal' then 'liberal professional'
      when emp_link = 'Autonomo' then 'self-employment'
      when emp_link = 'EstudanteBolsista' then 'scholarship holder'
      when emp_link = 'RendaAlugueis' then 'rental income'
      when emp_link = 'DiretorEmpresa' then 'company director'
		else emp_link end as employment_bond,
    number_of_dependents,
    case when current_situation = 'Familiares' then 'family'
      when current_situation = 'Alugado' then 'rented'
      when current_situation = 'Proprio' then 'own'
		else current_situation end as current_house_situation,
    has_contributed_to_current_house,
    case when gender = 'Feminino' then 'feminine' 
		  when gender = 'Masculino' then 'masculine'
		  else gender
		end as gender,
    marital_status,
    id_estado as id_state,
    dt_birth,
    ts_created,
    ts_updated,
    now() as ts_load
from datalake_ebdb_clean.proponent_proposal