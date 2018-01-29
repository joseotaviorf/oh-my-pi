drop view if exists public.vw_dim_property;
create or replace view public.vw_dim_property
as

with de_published_dates as ( 
    select distinct 
        vpl.id, 
        vpl.version, 
        vpl.min_version_time, 
        vpl.max_version_time, 
        vpl.status as last_status_version,
        ish.status_history, 
        max(ish.status_time) over (partition by ish.id, vpl.version) as de_publication_date
    from vw_property_listing vpl
    left join imovel_status_history ish
        on ish.id = vpl.id
          and ish.status_time between coalesce(vpl.min_version_time, '1900-01-01') 
                                  and coalesce(vpl.max_version_time, '2300-01-01')
          and ish.status_history = 'despublicado'
),
imovel_dates as
(
	SELECT 
		im.id,
	  pl.version,
	  pl.min_version_time,
	  pl.max_version_time,
	  pl.status as last_status_version,
	  pl.min_version_time::date as publication_date,
	  ud.de_publication_date,
	  pl.version as nr_listing,
		pl.nr_renting,
	  min(b."criadoEm") AS first_booking_date,
	  
	  min(b."criadoEm") 
	  	filter (
				where 
					b."criadoEm" > COALESCE(pl.min_version_time,'2000-01-01 00:00:00'::timestamp) 
					AND b."criadoEm" <= COALESCE(pl.max_version_time::timestamp, now())
			) 
		as version_first_booking_date,
	        
		min(b."criadoEm") 
			filter (
				where b.status::text <> 'Canceled'
			) 
		as first_booking_confirmed_date,
	       
		min(b."criadoEm") 
			filter (
				where	b.status::text <> 'Canceled'
				and b."criadoEm" > coalesce(pl.min_version_time,'2000-01-01 00:00:00'::timestamp) 
				and b."criadoEm" <= coalesce(pl.max_version_time::timestamp, now())
			) 
		as version_first_booking_confirmed_date,
	        
		min(v.dia) AS first_visit_date,
	        
		min(v.dia) 
			filter (
				where v.dia > coalesce(pl.min_version_time,'2000-01-01 00:00:00'::timestamp) 
				and v.dia <= COALESCE(pl.max_version_time::timestamp, now())
			) 
		AS version_first_visit_date,
	  
		min(v.dia) 
			filter (
				where	b.status::text <> 'Canceled'
			) 
		AS first_visit_confirmed_date,
	  
		min(v.dia) 
			filter (
				where b.status::text <> 'Canceled'
				and v.dia > coalesce(pl.min_version_time,'2000-01-01 00:00:00'::timestamp) 
				and v.dia <= coalesce(pl.max_version_time::timestamp, now())
			) 
		as version_first_visit_confirmed_date,
	        
		min(pp."criadoEm"::timestamp) AS first_pre_proposal_date,
	        
		min(pp."criadoEm"::timestamp) 
			filter (
				where	 
					pp."criadoEm"::timestamp > COALESCE(pl.min_version_time, '2000-01-01 00:00:00'::timestamp) 
					and pp."criadoEm"::timestamp <= COALESCE(pl.max_version_time::timestamp, now())
			) 
		as version_first_pre_proposal_date,
	        
	 	min(p."criadoEm") 
	 		filter (
	 			where p."statusDocumentacaoInq" = 'RecusadoCardiff'
 			) 
 		as first_proposal_refused_by_insurance_date,
	        
    min(p."criadoEm") 
    	filter (
				where p."statusDocumentacaoInq"::text = 'RecusadoCardiff'::text 
				and p."criadoEm" > COALESCE(pl.min_version_time, '2000-01-01 00:00:00'::timestamp) 
				and p."criadoEm" <= COALESCE(pl.max_version_time::timestamp, now())
			) 
		as version_first_proposal_refused_by_insurance_date,
	        
    min(p."criadoEm") AS first_proposal_accepted_date,
	        
  	min(p."criadoEm") 
  		filter (
				where p."criadoEm" > COALESCE(pl.min_version_time, '2000-01-01 00:00:00'::timestamp) 
				and p."criadoEm" <= COALESCE(pl.max_version_time::timestamp, now())
			) 
		as version_first_proposal_accepted_date,
	        
    min(c."criadoEm") AS first_contract_date,
	        
  	min(c."criadoEm") 
	  	filter (
				where c."criadoEm" > COALESCE(pl.min_version_time, '2000-01-01 00:00:00'::timestamp) 
				and c."criadoEm" <= COALESCE(pl.max_version_time::timestamp, now())
			) 
		AS version_first_contract_date,
	        
    min(c."dataAssinado") AS first_signed_contract_date,
	        
    min(c."dataAssinado") 
    	FILTER (
    		where c."dataAssinado" > COALESCE(pl.min_version_time, '2000-01-01 00:00:00'::timestamp) 
    		AND c."dataAssinado" <= COALESCE(pl.max_version_time::timestamp, now())
  		) 
		AS version_first_signed_contract_date,
	        
    min(p."dataDocumentosEnviados"::timestamp) as first_document_sent_date,
	        
    min(p."dataDocumentosEnviados"::timestamp) 
    	FILTER (
				WHERE p."dataDocumentosEnviados"::timestamp >	COALESCE(pl.min_version_time, '2000-01-01 00:00:00'::timestamp) 
				AND p."dataDocumentosEnviados"::timestamp <= COALESCE(pl.max_version_time::timestamp, now())
			) 
		AS version_first_document_sent_date,
	        
    max(p."dataDocumentosEnviados"::timestamp) as last_document_sent_date,
	        
    max(p."dataDocumentosEnviados"::timestamp) 
    	FILTER (
        WHERE p."dataDocumentosEnviados"::timestamp > COALESCE(pl.min_version_time, '2000-01-01 00:00:00'::timestamp) 
	    	AND p."dataDocumentosEnviados"::timestamp <= COALESCE(pl.max_version_time::timestamp, now())
  		)
	  AS version_last_document_sent_date
	
	FROM 
		imovel im
	       
	JOIN 
		vw_property_listing pl 
		ON pl.id = im.id
	
	LEFT JOIN 
		booking b 
		ON b.imovel_id = im.id
	         
	LEFT JOIN 
		visit v 
		ON v.id = b.visita_id
	
	LEFT JOIN 
		rental_flow fl 
		ON fl.id = b."fluxoLocacao_id"
	         
	LEFT JOIN 	
		pre_proposal pp 
		ON fl.imovel_id = pp.imovel_id
	
	LEFT JOIN 
		proposal p
		ON p."preProposta_id" = pp.id
	
	LEFT JOIN 
		contract c 
		ON c.proposta_id = p.id

	LEFT JOIN
	    de_published_dates ud
	    ON ud.id = pl.id
	      AND ud.version = pl.version
		
	GROUP BY 
		im.id, 
		pl.version, 
		pl.min_version_time, 
		pl.max_version_time,
	    pl.status,
	    pl.min_version_time::date,
	    pl.version,
		pl.nr_renting,
		ud.de_publication_date
)
SELECT 
	((i.id || '00') || COALESCE(imovel_dates.version, 1))::bigint AS sk_property,
  i.id,
  imovel_dates.version,
  imovel_dates.min_version_time,
  imovel_dates.max_version_time,
  imovel_dates.last_status_version,
  i.aluguel,
  i.bairro,
  i.cep,
  i.cidade,
  i.complemento,
  i.condominio,
  i.data_construcao,
  i.elevador,
  i.email_contato,
  i.email_sessao_fotos,
  i.endereco,
  i.estado_conservacao,
  i.fotografo_preenche_dados,
  i.iptu,
  i.lat,
  i.lng,
  i.mobiliado,
  i.nivel_acabamento,
  i.numero,
  i.numero_banheiros,
  i.numero_quartos,
  i.numero_suites,
  i.numero_vagas,
  i.porcentagem_cadastro_completa,
  i.prefere_email_sessao_fotos,
  i.status,
  i.tel_contato1,
  i.tel_contato2,
  i.tel_sessao_fotos,
  i.tipo,
  i.tipo_porteiro,
  i.tipo_vagas,
  i.verificado,
  i.usuario_id,
  i.codigo_promocao,
  i.cotar_seguro,
  i.valor_total,
  i.expiration_date,
  i.notificacao_anuncio_incompleto_proprietario,
  i.notificacao_anuncio_incompleto_admin,
  i.short_url,
  i.valor_seguro,
  i.plano_aceito,
  i.sugerir_reajuste_de_preco,
  i.permite_placa_aluga_se,
  i.prioridade_destaque_classificado,
  i.dados_administradora_condominio,
  i.condominio_incluso,
  i.coordenadas_manuais,
  i.iptu_incluso,
  i.followup_proprietario_subir_fotos,
  i.data_primeiro_verificado,
  i.tipo_colisao_lead,
  i.calculo_pagamento_lead_corretor,
  i.nome_imagem_capa,
  i.geo_hash,
  i.tipo_anuncio,
  i.calculo_pagamento_lead_afiliado,
  i.possui_banheiro_servico,
  i.possui_quarto_servico,
  i.bairro_padrao,
  i.tipo_condominio,
  i.tipo_iptu,
  i.disponivel_ate,
  i.flag_verificar_preco_comparando_com_media,
  i.sempre_consultar_proprietario_visita,
  i.email_publicacao_proprietario_enviado,
  i.status_conversao_imovel,
  i.ultimo_email_de_confirmacao_enviado,
  i.latlng,
  i.ultimo_update_indice,
  i.suspenso_ate,
  i.external_id,
  i.em_negociacao,
  i.em_negociacao_externa,
  i.entrou_em_negociacao_externa,
  i.motivo_recusa_cardiff,
  i.recaptado_em,
  i.job_fotografo_pendente,
  i.requisitou_fotos_profissionais,
  i.last_confirmation_availability,
  i.cartorio,
  i.penalization_score,
  i.receber_copia_contrato_padrao,
  i.rank_score,
  i.ultima_publicacao,
  i.confirmado_informacoes_visita,
  i.estado_abreviacao,
  i.estado_nome,
  i.dados_afiliado_tipo_afiliado,
  i.dados_afiliado_inicio_atuacao,
  i.dados_afiliado_cidade_atuacao,
  i.regiao_cidade,
  i.regiao_macro,
  i.regiao_sub,
  i.regiao_id,
  i.condominio_nome,
  i.local_nome,
  i.corretor_nome,
  i.etapa_data_web_caracteristicas,
  i.etapa_data_web_copiarmaisdados,
  i.etapa_data_web_fotos,
  i.etapa_data_web_uploadfotos,
  i.etapa_data_web_valores,
  i.etapa_data_mob_detalhes,
  i.etapa_data_mob_endereco,
  i.etapa_data_mob_fotos,
  i.etapa_data_mob_preco,
  i.etapa_data_mob_titulo,
  i.etapa_data_mob_visitas,
  i.etapa_data_mob_vistoria,
  COALESCE(h.dt_first_publication, i.first_publication) AS first_publication,
  imovel_dates.publication_date,
  imovel_dates.de_publication_date,
  imovel_dates.first_booking_date,
  imovel_dates.first_booking_confirmed_date,
  imovel_dates.first_visit_date,
  imovel_dates.first_visit_confirmed_date,
  imovel_dates.first_pre_proposal_date,
  imovel_dates.first_proposal_accepted_date,
  imovel_dates.first_proposal_refused_by_insurance_date,
  imovel_dates.first_contract_date,
  imovel_dates.first_signed_contract_date,
  imovel_dates.first_document_sent_date,
  imovel_dates.last_document_sent_date,
  imovel_dates.version_first_booking_date,
  imovel_dates.version_first_booking_confirmed_date,
  imovel_dates.version_first_visit_date,
  imovel_dates.version_first_visit_confirmed_date,
  imovel_dates.version_first_pre_proposal_date,
  imovel_dates.version_first_proposal_accepted_date,
  imovel_dates.version_first_proposal_refused_by_insurance_date,
  imovel_dates.version_first_contract_date,
  imovel_dates.version_first_signed_contract_date,
  imovel_dates.version_first_document_sent_date,
  imovel_dates.version_last_document_sent_date,
  
  date_part('epoch', imovel_dates.first_booking_confirmed_date - COALESCE(h.dt_first_publication, i.first_publication)) / 86400 AS time_listing_created_to_first_booking_realized,
  date_part('epoch', imovel_dates.first_signed_contract_date - COALESCE(h.dt_first_publication, i.first_publication)) / 86400 AS time_listing_created_to_first_contract_signed,
  date_part('epoch', imovel_dates.first_document_sent_date - COALESCE(h.dt_first_publication, i.first_publication)) / 86400 AS time_listing_created_to_first_documentation_sent,
  date_part('epoch', imovel_dates.first_proposal_accepted_date - COALESCE(h.dt_first_publication, i.first_publication)) / 86400 AS time_listing_created_to_first_offer_accepted,
  date_part('epoch', imovel_dates.first_pre_proposal_date - COALESCE(h.dt_first_publication, i.first_publication)) / 86400 AS time_listing_created_to_first_offer_submited,
  date_part('epoch', imovel_dates.first_proposal_accepted_date - COALESCE(h.dt_first_publication, i.first_publication)) / 86400 AS time_listing_created_to_first_refuse_by_security,
  date_part('epoch', imovel_dates.first_visit_date::timestamp - COALESCE(h.dt_first_publication, i.first_publication)) / 86400 AS time_listing_created_to_first_visit_realized,
  
  coalesce(imovel_dates.nr_listing, 0) as nr_listing,
  coalesce(imovel_dates.nr_renting, 0) as nr_renting,
  i.info_visita_autorizacao_de_entrada,
  i.info_visita_proprietario_acompanha,
  i.info_visita_estamos_liberados,
  i.info_visita_prop_precisa_liberar,
  i.info_visita_chave_box_quintoandar,
  i.data_criacao,
  i.atualizado_em,
  now() AS load_timestamp,
  i.usuario_que_cadastrou_id,
  
  i.imovel_v3 as property_v3,

  i.area_total as total_area,
  i.area_terreno as contruction_area,
  i.unpublished_reason as unpublished_reason

from 
	imovel i
     
left join 
	(
	  select
	  	a.id,
	    min(a.status_time) AS dt_first_publication
	  from imovel_status_history a
	  where a.published = 1
	  group by a.id
	) h 
	ON h.id = i.id
    
left join 
	imovel_dates 
	ON imovel_dates.id = i.id;
