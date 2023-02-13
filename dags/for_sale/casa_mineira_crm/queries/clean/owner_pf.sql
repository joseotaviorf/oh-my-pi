SELECT 
  id,
  proprietario_id AS id_owner,
  cpf,
  rg,
  profissao AS profession,
  estado_civil AS marital_status,
  conjuge_nome AS spouse_name,
  conjuge_email AS spouse_email,
  conjuge_telefone AS spouse_phone,
  conjuge_cpf AS spouse_cpf,
  conjuge_rg AS spouse_rg,
  conjuge_profissao AS spouse_profession,
  data_nascimento AS dt_birth,
  conjuge_data_nascimento AS dt_spouse_birth,
  CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
  datalake_casa_mineira_crm_raw.proprietario_pf