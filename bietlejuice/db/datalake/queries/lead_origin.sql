with lead_amplitude as (
	select  cast(regexp_extract(e_lead_id, '(^\d+)') as bigint) as id_lead,
	        '' as firestore_id,
			e_lead_id,
	        0 as rule_num,
	        '2 referral' as rule,
	        event_time,
	        u_utm_campaign,
	        u_utm_medium,
	        u_utm_source,
	        u_platform,
	        region,
	        city,
	        uuid,
			rank() over(partition by e_lead_id order by event_time) as rn
	from datalake_clean.amplitude_events ae
        where et in
            ('referral_confirmation_page_viewed',
            'referral_opportunity_confirmed',
            'referral_listing_confirmed',
            'referral_form_response_received')
            and	ym >= '2018-05'
            and ae.app = '205027'
            and regexp_like(e_lead_id, '(^\d+)') -- 379949 rows
	union
	select 	cast(regexp_extract(e__lead_id, '(^\d+)') as bigint) as id_lead,
	        '' as firestore_id,
            1 as rule_num,
            '3 referral_2' as rule,
            event_time,
            u_utm_campaign,
            u_utm_medium,
            u_utm_source,
            u_platform,
            region,
            city,
            uuid,
            rank() over(partition by e__lead_id order by event_time) as rn
	from datalake_clean.amplitude_events ae
        where et in ('Affiliate-Lead_referred',
						'Refer-Lead_referred' )
			and	ym >= '2018-05'
			and regexp_like(e__lead_id, '(^\d+)') --15475
	union
	select l.sk_lead,  2 as rule_num,  '1 firestore' as rule,  event_time, u_utm_campaign, u_utm_medium, u_utm_source, u_platform, region, city, uuid,
			rank() over(partition by u_lead_firestore_id order by event_time) as rn
	from staging.dim_lead_amplitude l
		join datalake_clean.amplitude_events ae
		on
			ym >= '2018-01'
			and app = '183047'
			and l.external_id = u_lead_firestore_id
			and trim(u_lead_firestore_id) <> '' --20374
	union
	select l.sk_lead,  3 as rule_num, '4 device' as rule,  event_time, u_utm_campaign, u_utm_medium, u_utm_source, u_platform, region, city, uuid,
			rank() over(partition by l.sk_lead order by event_time desc) as rn
	from staging.dim_lead_amplitude l
		join datalake_clean.amplitude_events ae
		on
			ym >= '2018-01'
			and l.owner_device_id = ae.device_id
			and cast(ae.event_time as timestamp) <= l.criado_em
			and	trim(device_id) <> ''
),
ordered as(
	select *,
		rank() over(partition by sk_lead order by rule_num, uuid) as rule_order
		FROM
		   lead_amplitude la
        where rn = 1
)
select
  dl.sk_lead,
  dl.id,
  dl.anuncio_criado_em,
  dl.area_total,
  dl.bairro,
  dl.captado_em,
  dl.cep,
  dl.cidade,
  dl.complemento,
  dl.endereco,
  dl.endereco_captado,
  dl.nome_anunciante,
  dl.numero,
  dl.numero_banheiros,
  dl.numero_quartos,
  dl.numero_suites,
  dl.url_anuncio,
  dl.valor,
  dl.telefone_anunciante,
  dl.valor_por_metro_quad,
  dl.valor_por_quartos,
  dl.tipo,
  dl.email,
  dl.email_captador,
  dl.telefone_captador,
  dl.hot,
  dl.proximo_followup,
  dl.gerado_a_partir_de_deduplicacao,
  dl.dentro_area_atuacao,
  dl.sistema_enviou_email_via_classificado,
  dl.lat,
  dl.lng,
  dl.condominio,
  dl.iptu,
  dl.reason,
  dl.reason_detail,
  dl.status,
  dl.envio_email_apresentacao_pos,
  dl.envio_email_apresentacao_pre,
  dl.processado,
  dl.origem,
  dl.external_id,
  dl.mencionar,
  dl.referencia,
  dl.automatically_discarded,
  dl.estado_nome,
  dl.estado_abrev,
  dl.lead_imobiliaria,
  dl.proprietario_nome,
  dl.proprietario_email,
  dl.dados_corretor_tipo_afiliado,
  dl.dados_corretor_nome,
  dl.dados_corretor_email,
  dl.dados_gerente_contas_nome,
  dl.dados_gerente_contas_email,
  dl.dados_afiliado_tipo_afiliado,
  dl.dados_afiliado_inicio_atuacao,
  dl.dados_afiliado_cidade_atuacao,
  dl.region_id,
  dl.atualizado_em,
  dl.criado_em,
  dl.url_source,
  case when la.uuid is not null then NULLIF(la.u_utm_source, '') else dl.utm_source end as utm_source,
  case when la.uuid is not null then NULLIF(la.u_utm_medium, '') else dl.utm_medium end as utm_medium,
  case when la.uuid is not null then NULLIF(la.u_utm_campaign, '') else dl.utm_campaign end as utm_campaign,
  dl.network,
  dl.usuario_que_indicou_id,
  dl.flg_city_served,
  dl.flg_latlng_served,
  dl.flg_location_served,
  dl.owner_device_id,
  NULLIF(la.uuid, '') as amplitude_event_id,
  NULLIF(la.region, '') as amplitude_event_region,
  NULLIF(la.city, '') as amplitude_event_city,
  NULLIF(la.u_platform, '') as platform,
  dl.load_timestamp
from
	staging.dim_lead_amplitude dl
left join
    ordered la
        on dl.sk_lead = la.sk_lead
        and rule_order = 1