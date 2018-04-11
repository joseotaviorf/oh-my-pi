DROP PROCEDURE IF EXISTS ebdb.list_fact_supply;

CREATE DEFINER = 'QuintoAndarMain'@'%'
PROCEDURE ebdb.list_fact_supply(IN _ref_date DATE)
BEGIN
select
	tbl.*,
	TIMESTAMPDIFF(MINUTE, dt_lead, dt_prospect) as lead_to_prospect_diff_minutes,
  TIMESTAMPDIFF(MINUTE, dt_prospect, dt_qualified) as prospect_to_qualified_diff_minutes,
  TIMESTAMPDIFF(MINUTE, dt_qualified, dt_opportunity) as qualified_to_opportunity_diff_minutes,
  TIMESTAMPDIFF(MINUTE, dt_opportunity, dt_first_listing) as opportunity_to_listing_diff_minutes,
  TIMESTAMPDIFF(MINUTE, dt_lead, dt_first_listing) as lead_to_listing_diff_minutes
from
(
	select
		CAST((@cnt := @cnt + 1) AS UNSIGNED) AS id,
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
		case
			when (base.lead_status = 'Descartado' and coalesce(jf.dataCriacao, jf.dataAgendamento, jf.dataAceitoFotografo, jf.dataUploadFotos) is null)
				then null
			else base.dt_qualified
		end as dt_qualified,
		coalesce(jf.dataCriacao, jf.dataAgendamento, jf.dataAceitoFotografo, jf.dataUploadFotos) as dt_opportunity,
		i.firstPublication as dt_first_listing,
		base.flow,
		base.acquisition_method,
		base.acquisition_channel
	from
	(
		select
			i.id as imovel_id,
			null as lead_id,
			null as lead_status,
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
			from_unixtime(ure.timestamp/1000) as dt_qualified,
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
			cl.id as conversao_id,
			i.usuarioQueCadastrou_id as rep_id,
			uda.id as affiliate_id,
			i.usuario_id as owner_id,
			i.regiao_id as region_id,
			coalesce(l.criadoEm, l.anuncioCriadoEm, l.captadoEm) as dt_lead,
			case
				when has_aud.id is not null then from_unixtime(ure.timestamp/1000)
				else coalesce(l.atualizadoEm, l.criadoEm) -- if there is no AUD records, we assume lead update or creation
			end as dt_prospect,
			case -- when excluded by specific reasons we count the lead as a qualified lead, even if its discarded
		    when cl.leadConvertido_id is not null
		    	then coalesce(cl.dataConversao, cl.criadoEm, from_unixtime(ure.timestamp/1000))
		    when l.reason in ('ProprietarioRecusou', 'Exclusivo')
		    	then coalesce(from_unixtime(dure.timestamp/1000), from_unixtime(ure.timestamp/1000))
		  end as qualified_date,
			'Lead Flow' as flow,
			'Non-Self Service' as acquisition_method,
			case
				when uda.id = 279289 then 'Doorman'
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
				where (a.processado = 1 or a.status_MOD = 1)
				  and a.status != 'Novo'
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
		  DadosAfiliado da
		  on da.id = l.afiliadoQueIndicou_id
		left join
		  Usuario uda
		  on uda.dadosAfiliado_id = da.id
		left join
			Lead old_lead
			on old_lead.id = l.old_id
	union all
		select
			i.id as imovel_id,
			null as lead_id,
			null as lead_status,
			cl.id as conversao_id,
			i.usuarioQueCadastrou_id as rep_id,
			null as affiliate_id,
			i.usuario_id as owner_id,
			i.regiao_id as region_id,
			i.dataCriacao as dt_lead,
			i.dataCriacao as dt_prospect,
			from_unixtime(ure.timestamp/1000) as dt_qualified,
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
		where leadConvertido_id is null
	) base
	left join
		(select imovel_id, min(id) as id from JobFotografo group by imovel_id) first_job
		on base.imovel_id = first_job.imovel_id
	left join
		JobFotografo jf
		on jf.id = first_job.id
	left join
		(select imovel_id, min(id) as id from JobFotografo where status = 'Publicado' group by imovel_id) photo_pub
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
	CROSS JOIN (SELECT @cnt := 0) AS dummy
) tbl;
END