drop view if exists vw_dim_user;
create view vw_dim_user
as
SELECT
  u.id as sk_user,
  u.id,
  nome,
  bairro,
  cargo,
  cep,
  cidade,
  complemento,
  cpf,
  cpf_validado_receita,
  data_inicio_empresa,

  case
      when date_part('year', data_nascimento) < 100 then data_nascimento + interval '1900 years' -- dateadd(year, 1900, data_nascimento)
      when date_part('year', data_nascimento) < 1000 then data_nascimento + interval '1000 years' -- dateadd(year, 1000, data_nascimento)
      else data_nascimento
  end as data_nascimento,

  email,
  email_alternativo,
  empresa,
  endereco,
  numero,
  facebook_id,
  linkedin_id,
  formacao_curso,
  formacao_escola,
  formacao_tipo,
  formacao_data_inicio,
  formacao_data_fim,
  novo_email,
  salario,
  sexo,
  telefone_principal,
  estado_abreviacao,
  estado_nome,
  contadorlogin,
  apelido,
  nao_me_prgunte_telefone,
  bloqueado,
  rg,
  tempo_resposta_medio_segundos,
  estado_civil,
  nacionalidade,
  profissao,
  salesforce_contato_id,
  detalhes_lead_busca_guiada,
  recebeu_busca_guiada,
  dadosagente_email_coordinator,
  dadosagente_cidade,
  dadosagente_atuacao,
  dadosagente_perfil,
  dadosagente_numero_creci,
  dadosagente_ativo,
  aceita_sms,
  salesforce_account_id,
  preferencia_contato,
  prefere_contato,
  data_clickanuncie,
  dadosbancarios_banco_codigo,
  dadosbancarios_banco,
  dadosbancarios_agencia,
  dadosbancarios_conta_corrente,
  dadosbancarios_cpf_cnpj,
  dadosbancarios_nome,
  dadosbancarios_outro_titular,
  dadosbancarios_tipo_conta,
  nao_enviar_aviso_mensal_procura,
  cod_ativacao_sms,
  data_geracao_cod_sms,
  emailsf,
  tipo_admin,
  last_update_oportunidade,
  data_avisado_condicoes_cardiff,
  data_captadora_enviou_email,
  data_enviado_app_e_cardiff,
  google_id,
  account_kit_id,
  dadosfotografo_inicio_contrato,
  dadosfotografo_tipo_contrato,
  dadosfotografo_preferencia_pagamento,
  dadosfotografo_ativo,
  dadosvendedor_inicio_contrato,
  dadosvendedor_nome_gerente,
  dadosafiliado_contador_planilha_leads,
  dadosafiliado_contratos_fechados,
  dadosafiliado_indicacao_shorturl,
  dadosafiliado_inicio_atuacao,
  dadosafiliado_ultim_calculo_comissao_indicado,
  dadosafiliado_verificado,
  dadosafiliado_tipo,
  dadosafiliado_cidade_atuacao,
  dadosafiliado_principais_bairros_atuacao,
  dadosafiliado_preferencia_pagamento,
  dadosafiliado_numero_creci,
  dadosafiliado_semana_ultima_comunicacao_balanco,
  dadosafiliado_id_planilha_gdocs,
  dadosafiliado_ativo,
  dadosgerentecontas_inicio_contrato,
  dadosgerentecontas_nome,
  active,
  dados_agente_id,
  dados_fotografo_id,
  dados_vendedor_id,
  dados_afiliado_id,
  tem_imovel,
  tem_app_inquilino,
  tem_contrato_ativo,
  inquilino,
  user_dates.first_booking_date,
  user_dates.first_booking_confirmed_date,
  user_dates.first_visit_date,
  user_dates.first_visit_confirmed_date,
  user_dates.first_pre_proposal_date,
  user_dates.first_proposal_accepted_date,
  user_dates.first_contract_date,
  user_dates.first_signed_contract,
  u.first_dt_document_sent,
  u.last_dt_document_sent,
  u.first_dt_sent_to_insurance,
  criado_em,
  atualizado_em,
  now() as load_timestamp,
  aie.network
FROM
  public.usuario u
inner join
(
  select
      u.id,
      min(b."criadoEm") as first_booking_date,
      min(b."criadoEm") filter (where b.status != 'Canceled') as first_booking_confirmed_date,
      min(v.dia) as first_visit_date,
      min(v.dia) filter (where b.status != 'Canceled') as first_visit_confirmed_date,
      min(pp."criadoEm") as first_pre_proposal_date,
      min(p."criadoEm") as first_proposal_accepted_date,
      min(c."criadoEm") as first_contract_date,
      min(c."dataAssinado") as first_signed_contract
  from
      usuario  u
  left join
      booking b
      on b.visitante_id = u.id
  left join
      visit v
      on v.id = b.visita_id
  left join
      rental_flow fl
      on fl.id = b."fluxoLocacao_id"
  left join
      pre_proposal pp
      on fl.cliente_id = pp.usuario_id
  left join
      proposal p
      on p."preProposta_id" = pp.id
  left join
      contract c
      on c.proposta_id = p.id

  group by
      u.id
) user_dates
on user_dates.id = u.id
left join 
  vw_amplitude_install_events aie
on u.id = aie.user_id
;

-- select data_nascimento from vw_dim_user