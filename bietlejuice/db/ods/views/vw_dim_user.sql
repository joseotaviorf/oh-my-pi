--drop view if exists vw_dim_user;
--create or replace view vw_dim_user as
SELECT
  u.id as sk_user,
  u.id,
  left(nome, 200) as nome,
  bairro,
  cep,
  cidade,
  complemento,
  cpf,
  CAST(CASE
      WHEN DATE_PART('year', data_nascimento) < 100 THEN data_nascimento + INTERVAL '1900 years' -- dateadd(year, 1900, data_nascimento)
      WHEN DATE_PART('year', data_nascimento) < 1000 THEN data_nascimento + INTERVAL '1000 years' -- dateadd(year, 1000, data_nascimento)
      ELSE data_nascimento
  END AS DATE) AS data_nascimento,
  email,
  email_alternativo,
  endereco,
  numero,
  facebook_id,
  linkedin_id,
  sexo,
  telefone_principal,
  estado_abreviacao,
  estado_nome,
  bloqueado,
  rg,
  dadosagente_perfil,
  dadosagente_numero_creci,
  dadosagente_ativo,
  aceita_sms,
  data_clickanuncie,
  dadosbancarios_banco_codigo,
  dadosbancarios_banco,
  dadosbancarios_agencia,
  dadosbancarios_conta_corrente,
  dadosbancarios_cpf_cnpj,
  dadosbancarios_nome,
  dadosbancarios_outro_titular,
  dadosbancarios_tipo_conta,
  tipo_admin,
  google_id,
  dadosfotografo_inicio_contrato,
  dadosfotografo_tipo_contrato,
  dadosfotografo_ativo,
  dadosvendedor_inicio_contrato,
  dadosafiliado_inicio_atuacao,
  dadosafiliado_cidade_atuacao,
  dadosafiliado_preferencia_pagamento,
  dadosafiliado_numero_creci,
  dadosafiliado_semana_ultima_comunicacao_balanco,
  dadosafiliado_ativo,
  active,
  dados_agente_id,
  dados_fotografo_id,
  dados_vendedor_id,
  dados_afiliado_id,
  flg_doorman_affiliate,
  coalesce(to_char(dt_doorman_joined, 'YYYYMMDD')::integer, -1) as sk_doorman_joined_date,
  tem_imovel,
  tem_app_inquilino,
  tem_contrato_ativo,
  inquilino,
  u.is_sale_agent::int::boolean,
  u.is_rent_agent::int::boolean,
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
  an.network,
  b_counts.visits_booked,
  b_counts.visits_realized,
  b_counts.visits_expected_to_happen
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
	      min(c.ts_created) as first_contract_date,
	      min(c.ts_signature) as first_signed_contract
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
	      on c.id_proposal = p.id
	  group by
	      u.id
	) user_dates
	on user_dates.id = u.id
left join
  app_network an
	on u.id = an.user_id
left join
	(
		select
			visitante_id,
			count(1) as visits_booked,
			sum(case when "fupVisita" in ('NaoGostou', 'Talvez', 'VaiNegociar', 'VisitouSozinho') then 1 else 0 end) as visits_realized,
			sum(case when "fupVisita" is not null then 1 else 0 end) as visits_expected_to_happen
		from booking
		group by
		visitante_id
	) b_counts
	on b_counts.visitante_id = u.id
;
