SELECT 
  id,
  proprietario_id AS id_owner,
  cnpj,
  inscricao_estadual AS state_registration,
  responsavel_nome AS responsible_name,
  responsavel_email AS responsible_email,
  responsavel_telefone AS responsible_phone,
  responsavel_cpf AS responsible_cpf,
  responsavel_rg AS responsible_rg,
  responsavel_profissao AS responsible_profession,
  responsavel_estado_civil AS responsible_marital_status,
  responsavel_data_nascimento AS dt_responsible_birth,
  CAST(criado_em AS TIMESTAMP) AS ts_created
FROM
  datalake_casa_mineira_crm_raw.proprietario_pj