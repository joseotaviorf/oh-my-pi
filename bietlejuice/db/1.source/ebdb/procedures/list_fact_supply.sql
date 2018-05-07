-- DROP PROCEDURE IF EXISTS ebdb.list_fact_supply;

CREATE DEFINER = 'QuintoAndarMain'@'%'
PROCEDURE ebdb.list_fact_supply(IN _ref_date DATE)
BEGIN
select
	id,
	lead_id,
	conversao_id,
	photo_job_id,
	imovel_id,
	rep_id,
	affiliate_id,
	owner_id,
	region_id,
	photographer_id,
	dt_lead,
	dt_prospect,
	dt_first_inside_sales_contact,
	dt_conversion, -- for inside sales analysis
	dt_qualified,
	dt_opportunity,
	dt_first_listing,
	flow,
	acquisition_method,
	acquisition_channel,
	case
		when (dt_first_listing is not null) then 'Listed'
		when (dt_opportunity is not null and dt_first_listing is null) and photo_job_status in ('FotosTiradas','Completado', 'NaoListado') then 'NotListedYet'
		when (dt_opportunity is not null and dt_first_listing is null and photo_job_status in ('Agendado','Iniciado','Novo')) then 'PhotoJobScheduled'
		when (dt_opportunity is not null and dt_first_listing is null and photo_job_status = 'Cancelado') then coalesce(photo_job_reason, 'CancelledPhotoJob')
		when (dt_opportunity is not null and dt_first_listing is null) then coalesce(photo_job_reason, 'CancelledPhotoJob')
		when (dt_opportunity is null and dt_qualified is not null and lead_status = 'Descartado') then lead_status
		when (dt_opportunity is null and dt_qualified is not null and lead_status = 'Convertido') then 'NoPhotoJob'
		when (dt_opportunity is null and dt_qualified is not null and conversao_id is not null) then 'NoPhotoJob'
		when (dt_opportunity is null and lead_reason in ('ProprietarioAvaliando', 'ProprietarioNaoAtende', 'ProprietarioVaiAnunciar')) then 'OnHold'
		when (dt_qualified is null and lead_status = 'Descartado') then coalesce(lead_reason, 'DiscardedLead')
		when (dt_qualified is null and lead_status = 'Novo') then 'LeadNotProcessed'
		when (flow = 'Lead Flow' and dt_qualified is null) then 'LeadNotProcessed'
		when (lead_status = 'Convertido' and conversao_id is null) then 'BrokenLeadFlow'
		when (flow = 'Lead Flow' and dt_prospect is null and lead_status is null) then 'DiscardedLead'
		when (flow = 'Self Service Flow' and dt_prospect is not null and dt_qualified is null) then 'TermsNotAccepted'
		when (flow = 'Self Service Flow' and dt_qualified is not null and dt_opportunity is null) then 'NoPhotoJob'
		when (flow = 'Organic Flow' and dt_prospect is not null and dt_qualified is null) then 'UnfinishedForm'
		when (flow = 'Organic Flow' and dt_qualified is not null and dt_opportunity is null) then 'NoPhotoJob'
		else 'NotMapped'
	end as funnel_step,
	TIMESTAMPDIFF(MINUTE, dt_lead, dt_prospect) as lead_to_prospect_diff_minutes,
  TIMESTAMPDIFF(MINUTE, dt_prospect, dt_qualified) as prospect_to_qualified_diff_minutes,
	TIMESTAMPDIFF(MINUTE, dt_lead, dt_first_inside_sales_contact) as lead_to_first_inside_sales_contact_diff_minutes,
  TIMESTAMPDIFF(MINUTE, dt_prospect, dt_first_inside_sales_contact) as prospect_to_first_inside_sales_contact_diff_minutes,
  TIMESTAMPDIFF(MINUTE, dt_qualified, dt_opportunity) as qualified_to_opportunity_diff_minutes,
  TIMESTAMPDIFF(MINUTE, dt_opportunity, dt_first_listing) as opportunity_to_listing_diff_minutes,
  TIMESTAMPDIFF(MINUTE, dt_lead, dt_first_listing) as lead_to_listing_diff_minutes,
	round(TIMESTAMPDIFF(MINUTE, dt_lead, dt_prospect)/60,1) as lead_to_prospect_diff_hours,
  round(TIMESTAMPDIFF(MINUTE, dt_prospect, dt_qualified)/60,1) as prospect_to_qualified_diff_hours,
	round(TIMESTAMPDIFF(MINUTE, dt_lead, dt_first_inside_sales_contact)/60,1) as lead_to_first_inside_sales_contact_hours,
  round(TIMESTAMPDIFF(MINUTE, dt_prospect, dt_first_inside_sales_contact)/60,1) as prospect_to_first_inside_sales_contact_diff_hours,
  round(TIMESTAMPDIFF(MINUTE, dt_qualified, dt_opportunity)/60,1) as qualified_to_opportunity_diff_hours,
  round(TIMESTAMPDIFF(MINUTE, dt_opportunity, dt_first_listing)/60,1) as opportunity_to_listing_diff_hours,
  round(TIMESTAMPDIFF(MINUTE, dt_lead, dt_first_listing)/60,1) as lead_to_listing_diff_hours,
	round(TIMESTAMPDIFF(MINUTE, dt_lead, dt_prospect)/1440,1) as lead_to_prospect_diff_days,
  round(TIMESTAMPDIFF(MINUTE, dt_prospect, dt_qualified)/1440,1) as prospect_to_qualified_diff_days,
	round(TIMESTAMPDIFF(MINUTE, dt_lead, dt_first_inside_sales_contact)/1440,1) as lead_to_first_inside_sales_contact_days,
  round(TIMESTAMPDIFF(MINUTE, dt_prospect, dt_first_inside_sales_contact)/1440,1) as prospect_to_first_inside_sales_contact_diff_days,
  round(TIMESTAMPDIFF(MINUTE, dt_qualified, dt_opportunity)/1440,1) as qualified_to_opportunity_diff_days,
  round(TIMESTAMPDIFF(MINUTE, dt_opportunity, dt_first_listing)/1440,1) as opportunity_to_listing_diff_days,
  round(TIMESTAMPDIFF(MINUTE, dt_lead, dt_first_listing)/1440,1) as lead_to_listing_diff_days,
  exclusivity+0 as exclusivity
from
(
	select
		CAST((@cnt := @cnt + 1) AS UNSIGNED) AS id,
		base.lead_reason,
		base.lead_status,
		jf2.status as photo_job_status,
		jf2.problema as photo_job_reason,
		base.lead_id,
		base.conversao_id,
		jf2.id as photo_job_id,
		base.imovel_id,
		base.rep_id,
		base.affiliate_id,
		base.owner_id,
		base.region_id,
		photographer.id as photographer_id,
		base.dt_lead,
		base.dt_prospect,
		base.dt_first_inside_sales_contact,
		base.dt_conversion,
		case
			when (base.lead_status = 'Descartado' and coalesce(jf.dataCriacao, jf.dataAgendamento, jf.dataAceitoFotografo, jf.dataUploadFotos) is null)
				then null
			else base.dt_qualified
		end as dt_qualified,
		coalesce(jf.dataCriacao, jf.dataAgendamento, jf.dataAceitoFotografo, jf.dataUploadFotos) as dt_opportunity,
		i.firstPublication as dt_first_listing,
		base.flow,
		base.acquisition_method,
		base.acquisition_channel,
		(sc.id is not null and optedOutAt is null) as exclusivity
	from
	(
		select
			i.id as imovel_id,
			null as lead_id,
			null as lead_status,
			null as lead_reason,
			null as conversao_id,
			case
				when (i.usuarioQueCadastrou_id=i.usuario_id and u.tipoAdmin = 'Normal' and u.email not like '%quintoandar%')
				then NULL
				else i.usuarioQueCadastrou_id
			end as rep_id,
			null as affiliate_id,
			i.usuario_id as owner_id,
			i.regiao_id as region_id,
			i.dataCriacao as dt_lead,
			i.dataCriacao as dt_prospect,
			null as dt_first_inside_sales_contact,
			null as dt_conversion,
			case
				when (i.usuarioQueCadastrou_id=i.usuario_id and u.tipoAdmin = 'Normal' and u.email not like '%quintoandar%')
				then from_unixtime(ure.timestamp/1000)
				else i.dataCriacao
			end as dt_qualified,
			case
				when (i.usuarioQueCadastrou_id=i.usuario_id and u.tipoAdmin = 'Normal' and u.email not like '%quintoandar%')
				then 'Self Service Flow'
				else 'Organic Flow'
			end as flow,
			case
				when (i.usuarioQueCadastrou_id=i.usuario_id and u.tipoAdmin = 'Normal' and u.email not like '%quintoandar%')
				then 'Self-Service'
				else 'Non-Self Service'
			end as acquisition_method,
			case
				when (i.usuarioQueCadastrou_id=i.usuario_id and u.tipoAdmin = 'Normal' and u.email not like '%quintoandar%')
				then 'Owner App'
				else 'Admin'
			end as acquisition_channel
		from
			Imovel i
		left join
			ConversaoLead cl
			on cl.imovel_id = i.id
		left join
			Usuario u
			on u.id = i.usuarioQueCadastrou_id
		left join
		 	(
		 		select
		      min(REV) as REV,
		      garantias,
		      Imovel_id
		    from
		    	Imovel_garantias_AUD
		    where garantias in ('SeguroFiancaCardiff','SeguroFairfax')
		    group by Imovel_id
		  ) ig
		  on i.id = ig.Imovel_id
		  and ig.garantias in ('SeguroFiancaCardiff','SeguroFairfax')
		left join
		  UsuarioRevisionEntity ure
		  on ig.REV = ure.id
		where cl.id is null
	union all
		select
			i.id as imovel_id,
			l.id as lead_id,
			l.status as lead_status,
			l.reason as lead_reason,
			cl.id as conversao_id,
			i.usuarioQueCadastrou_id as rep_id,
			uda.id as affiliate_id,
			i.usuario_id as owner_id,
			coalesce(i.regiao_id, pr.regiao_id) as region_id,
			coalesce(l.criadoEm, l.anuncioCriadoEm, l.captadoEm) as dt_lead,
			case
				when has_aud.id is not null then from_unixtime(ure.timestamp/1000)
				else coalesce(l.atualizadoEm, l.criadoEm) -- if there is no AUD records, we assume lead update or creation
			end as dt_prospect,
			isc.dt dt_first_inside_sales_contact,
			coalesce(cl.dataConversao, cl.criadoEm) as dt_conversion,
			case -- when excluded by specific reasons we count the lead as a qualified lead, even if its discarded
		    when cl.leadConvertido_id is not null
		    	then coalesce(cl.dataConversao, cl.criadoEm, from_unixtime(ure.timestamp/1000))
		    when l.reason in ('ProprietarioRecusou', 'Exclusivo')
		    	then coalesce(from_unixtime(dure.timestamp/1000), from_unixtime(ure.timestamp/1000))
		  end as dt_qualified,
			'Lead Flow' as flow,
			'Non-Self Service' as acquisition_method,
			case
				when uda.id = 279289 and l.origem <> 'Reprocessado' then 'Doorman'
		    when l.tipo = 'Afiliado' and l.origem = 'App' then 'Affiliate App'
		    when l.tipo = 'Afiliado' and l.origem = 'Form' then 'Affiliate Form'
		    when l.tipo = 'Afiliado' and l.origem = 'Planilha' then 'Affiliate Spreadsheet'
		    when l.tipo = 'Afiliado' and l.origem = 'Desconhecida' then 'Affiliate Unknown'
		    when l.tipo = 'OpenLink' and l.origem = 'Landing' then 'Direct Referral'
		    when l.origem = 'Facebook' then 'Facebook'
		    when l.origem = 'Landing' then 'Landing Page Leads' -- BrokenOpenLink goes here also
		    when l.origem = 'Crawling' then 'Crawling'
		    when l.origem = 'Reprocessado' and old_lead.origem = 'Landing' then 'Reprocessed Landing'
		    when l.origem = 'Reprocessado' and old_lead.tipo = 'Afiliado' then 'Reprocessed Affiliate'
		    when l.origem = 'Reprocessado' then 'Reprocessed Others'
		    else 'Other'
		  end as acquisition_channel
		from
			(
				select
					*,
					case
			 			when SUBSTRING_INDEX(infosExtras,';',1) REGEXP '^-?[0-9]+$'
			 				then SUBSTRING_INDEX(infosExtras,';',1)
			 			else NULL
			 		end as old_id
		 		from Lead
			) l -- all data from Lead table plus a reprocessed Extra Field
		left join
			ConversaoLead cl
			on cl.leadConvertido_id = l.id
		left join
			Imovel i
			on i.id = cl.imovel_id
		left join
			(
        select
          a.id,
          min(a.REV) as REV
        from
          Lead_AUD a
        where ((a.processado = 1 and a.processado_MOD = 1) or (a.status_MOD = 1 and a.status != 'Novo'))
          and coalesce(a.automaticallyDiscarded, 0) = 0
        group by a.id
      ) first_update
			on first_update.id = l.id
		left join
		  Lead_AUD la
		  on la.id = l.id
		  and la.REV = first_update.REV
		left join
		  UsuarioRevisionEntity ure
		  on ure.id = la.REV
		left join
			(select max(REV) as REV, id from Lead_AUD where status_MOD = 1 and status = 'Descartado' group by id) discard
			on l.id = discard.id
		left join
		  UsuarioRevisionEntity dure
		  on dure.id = discard.REV
		left join
		 	(select max(REV) as REV, id from Lead_AUD group by id) has_aud
		 	on has_aud.id = l.id
		left join
			(
				select
					la.id,
					min(FROM_UNIXTIME(ure.timestamp/1000)) as dt
				from
					Lead_AUD la
				left join
					UsuarioRevisionEntity ure
					on ure.id = la.REV
				left join
					Usuario u
					on u.id = ure.usuario_id
				where
					(u.dadosVendedor_id is not null)
				group by la.id
			) isc
			on isc.id = l.id
		left join
		  DadosAfiliado da
		  on da.id = l.afiliadoQueIndicou_id
		left join
		  Usuario uda
		  on uda.dadosAfiliado_id = da.id
		left join
			Lead old_lead
			on old_lead.id = l.old_id
		left join -- trying to find regions for leads using lat lng with the region polygons
			(
				SELECT
					p.*,
					r.cidadeNome as cidade
				FROM PoligonoRegiao p
				left join (
										select
											max(pr.id) as id
										from PoligonoRegiao pr
										left join MapRegiao mr on pr.regiao_id = mr.id
										where mr.id is not null
										group by poligono
									) latest on latest.id = p.id
				left join MapRegiao r on r.id = p.regiao_id
				where latest.id is not null
			) pr
			on pr.cidade = l.cidade -- to avoid too much processing
			and ST_Contains(
						ST_GeometryFromText(ST_AsText(pr.poligono)),
						ST_GeometryFromText(concat('Point(',coalesce(i.lng,l.lng),' ',coalesce(i.lat,l.lat),')'))
					) = 1
	union all
		select
			i.id as imovel_id,
			null as lead_id,
			null as lead_status,
			null as lead_reason,
			cl.id as conversao_id,
			i.usuarioQueCadastrou_id as rep_id,
			null as affiliate_id,
			i.usuario_id as owner_id,
			i.regiao_id as region_id,
			i.dataCriacao as dt_lead,
			i.dataCriacao as dt_prospect,
			coalesce(cl.dataConversao, cl.criadoEm) as dt_first_inside_sales_contact,
			coalesce(cl.dataConversao, cl.criadoEm) as dt_conversion,
			coalesce(cl.dataConversao, cl.criadoEm) as dt_qualified,
			'Organic Flow' as flow,
			'Non-Self Service' as acquisition_method,
			'Inside Sales' as acquisition_channel
		from
			ConversaoLead cl
		left join
			Imovel i
			on i.id = cl.imovel_id
		left join
			Usuario u
			on u.id = i.usuarioQueCadastrou_id
		where leadConvertido_id is null
	) base
	left join
		(select imovel_id, min(id) as id from JobFotografo group by imovel_id) first_job
		on base.imovel_id = first_job.imovel_id
	left join
		JobFotografo jf
		on jf.id = first_job.id
	left join
		(select imovel_id, max(id) as id from JobFotografo group by imovel_id) photo_pub
		on base.imovel_id = photo_pub.imovel_id
	left join
		JobFotografo jf2
		on jf2.id = photo_pub.id
	left join
		Usuario photographer
		on photographer.dadosFotografo_id = jf2.dadosFotografo_id
	left join
		Imovel i
		on i.id = base.imovel_id
	left join
		(select max(id) as id, imovel_id from SpecialCondition group by imovel_id) maxsc
		on maxsc.imovel_id = i.id
	left join
		SpecialCondition sc
		on sc.id = maxsc.id
	CROSS JOIN (SELECT @cnt := 0) AS dummy
) tbl;
END