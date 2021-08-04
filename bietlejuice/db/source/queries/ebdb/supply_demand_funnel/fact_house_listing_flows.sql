select
	id,
	lead_id,
	conversao_id,
	photo_job_id,
	imovel_id,
	rep_id,
	isales_registrant_id,
	affiliate_id,
	region_id,
	first_region_id,
	dt_lead,
	dt_prospect,
	dt_first_contact,
	dt_conversion,
	dt_qualified,
	dt_opportunity,
	dt_first_listing,
	dt_discarded,
	user_id_lead_first_discarder,
	user_id_lead_last_discarder,
	is_self_service_photo_job_scheduled,
	flow,
	acquisition_method,
	acquisition_channel,
	acquisition_source,
	case
		when (dt_first_listing is not null) then 'Listed'
		when (dt_opportunity is not null and dt_first_listing is null) and photo_job_status in ('FotosTiradas','Completado', 'NaoListado') then 'NotListedYet'
		when (dt_opportunity is not null and dt_first_listing is null and photo_job_status in ('Agendado','Iniciado','Novo')) then 'PhotoJobScheduled'
		when (dt_opportunity is not null and dt_first_listing is null and photo_job_status = 'Cancelado') then coalesce(photo_job_reason, 'CancelledPhotoJob')
		when (dt_opportunity is not null and dt_first_listing is null) then coalesce(photo_job_reason, 'CancelledPhotoJob')
		when (dt_opportunity is null and dt_qualified is not null and lead_status = 'Descartado') then 'DiscardedQualified'
		when (dt_opportunity is null and dt_qualified is not null and lead_status = 'Convertido') then 'NoPhotoJob'
		when (dt_opportunity is null and dt_qualified is not null and conversao_id is not null) then 'NoPhotoJob'
		when (dt_opportunity is null and lead_reason = 'EmProspeccao') then 'OnHold'
		when (dt_qualified is null and lead_status = 'Descartado') then 'DiscardedProspect'
		when (dt_qualified is null and lead_status = 'Novo' and cidade = 'Outra cidade') then 'NaoProcessadoArea'
		when (dt_qualified is null and lead_status = 'Novo') then 'NaoProcessado'
		when (flow = 'Lead Flow' and dt_qualified is null) then 'NaoProcessado'
		when (lead_status = 'Convertido' and conversao_id is null) then 'BrokenLeadFlow'
		when (flow = 'Lead Flow' and dt_prospect is null and lead_status is null) then 'DiscardedLead'
		when (flow = 'Self-Service Flow' and dt_prospect is not null and dt_qualified is null) then 'TermsNotAccepted'
		when (flow = 'Self-Service Flow' and dt_qualified is not null and dt_opportunity is null) then 'NoPhotoJob'
		when (flow = 'Organic Flow' and dt_prospect is not null and dt_qualified is null) then 'UnfinishedForm'
		when (flow = 'Organic Flow' and dt_qualified is not null and dt_opportunity is null) then 'NoPhotoJob'
		else 'NotMapped'
	end as funnel_step,
	round(TIMESTAMPDIFF(MINUTE, dt_lead, dt_prospect)/60,1) as hours_lead_to_prospect,
  round(TIMESTAMPDIFF(MINUTE, dt_prospect, dt_qualified)/60,1) as hours_prospect_to_qualified,
	round(TIMESTAMPDIFF(MINUTE, dt_lead, dt_first_contact)/60,1) as hours_lead_to_first_contact,
  round(TIMESTAMPDIFF(MINUTE, dt_prospect, dt_first_contact)/60,1) as hours_prospect_to_first_contact,
  round(TIMESTAMPDIFF(MINUTE, dt_qualified, dt_opportunity)/60,1) as hours_qualified_to_opportunity,
  round(TIMESTAMPDIFF(MINUTE, dt_opportunity, dt_first_listing)/60,1) as hours_opportunity_to_listing,
  round(TIMESTAMPDIFF(MINUTE, dt_lead, dt_first_listing)/60,1) as hours_lead_to_listing,
	round(TIMESTAMPDIFF(MINUTE, dt_lead, dt_prospect)/1440,1) as days_lead_to_prospect,
  round(TIMESTAMPDIFF(MINUTE, dt_prospect, dt_qualified)/1440,1) as days_prospect_to_qualified,
	round(TIMESTAMPDIFF(MINUTE, dt_lead, dt_first_contact)/1440,1) as days_lead_to_first_contact,
  round(TIMESTAMPDIFF(MINUTE, dt_prospect, dt_first_contact)/1440,1) as days_prospect_to_first_contact,
  round(TIMESTAMPDIFF(MINUTE, dt_qualified, dt_opportunity)/1440,1) as days_qualified_to_opportunity,
  round(TIMESTAMPDIFF(MINUTE, dt_opportunity, dt_first_listing)/1440,1) as days_opportunity_to_listing,
  round(TIMESTAMPDIFF(MINUTE, dt_lead, dt_first_listing)/1440,1) as days_lead_to_listing,
  case when (dt_conversion is null and dt_discarded is null) then null else
        round(TIMESTAMPDIFF(MINUTE, dt_lead, least(coalesce(dt_conversion, DATE_ADD(date(dt_discarded), INTERVAL 1 DAY)),
                                                    coalesce(dt_discarded, DATE_ADD(date(dt_conversion), INTERVAL 1 DAY))))/1440,1)
       end as days_lead_to_processing
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
		coalesce(base.rep_id, photo_rep_ure.usuario_id) as rep_id,
		base.rep_id as isales_registrant_id,
		base.affiliate_id,
		base.owner_id,
		base.region_id,
		base.first_region_id as first_region_id,
		photographer.id as photographer_id,
		base.dt_lead,
		base.dt_prospect,
		base.dt_first_contact,
		base.dt_conversion,
		case
			when (
				base.lead_status = 'Descartado'
				and coalesce(jf.dataCriacao, jf.dataAgendamento, jf.dataAceitoFotografo, jf.dataUploadFotos) is null
				and ( (base.lead_reason = 'ProprietarioRecusou' and base.reason = 'OWNER_DIDNT_LISTEN_TO_PITCH') OR 
					(base.lead_reason != 'ProprietarioRecusou') ) )
				then null
			else base.dt_qualified
		end as dt_qualified,
		coalesce(jf.dataCriacao, jf.dataAgendamento, jf.dataAceitoFotografo, jf.dataUploadFotos) as dt_opportunity,
		i.firstPublication as dt_first_listing,
		dt_discarded,
		user_id_lead_first_discarder,
		user_id_lead_last_discarder,
		base.flow,
		base.acquisition_method,
		base.acquisition_channel,
		base.acquisition_source,
		l.cidade,
		l.bairro,
		(first_rev_photo_job_user.id is not null) as is_self_service_photo_job_scheduled
	from
	(
		select
			i.id as imovel_id,
			null as lead_id,
			null as lead_status,
			null as lead_reason,
			null as reason,
			null as conversao_id,
			case
				when (coalesce(i.originalUsuarioQueCadastrou_id, i.usuarioQueCadastrou_id)=i.usuario_id and u.tipoAdmin = 'Normal' and u.email not like '%quintoandar%')
				then NULL
				else coalesce(i.originalUsuarioQueCadastrou_id, i.usuarioQueCadastrou_id)
			end as rep_id,
			null as affiliate_id,
			i.usuario_id as owner_id,
			i.regiao_id as region_id,
			i.regiao_id as first_region_id,
			i.dataCriacao as dt_lead,
			i.dataCriacao as dt_prospect,
			null as dt_first_contact,
			null as dt_conversion,
			case
				when (coalesce(i.originalUsuarioQueCadastrou_id, i.usuarioQueCadastrou_id)=i.usuario_id and u.tipoAdmin = 'Normal' and u.email not like '%quintoandar%')
				then from_unixtime(ure.timestamp/1000)
				else i.dataCriacao
			end as dt_qualified,
			null as dt_discarded,
			null as user_id_lead_first_discarder,
			null as user_id_lead_last_discarder,
			case
				when (coalesce(i.originalUsuarioQueCadastrou_id, i.usuarioQueCadastrou_id)=i.usuario_id and u.tipoAdmin = 'Normal' and u.email not like '%quintoandar%')
				then 'Self-Service Flow'
				else 'Organic Flow'
			end as flow,
			case
				when (coalesce(i.originalUsuarioQueCadastrou_id, i.usuarioQueCadastrou_id)=i.usuario_id and u.tipoAdmin = 'Normal' and u.email not like '%quintoandar%')
				then 'Self-Service'
				else 'Non-Self Service'
			end as acquisition_method,
			case
				when (coalesce(i.originalUsuarioQueCadastrou_id, i.usuarioQueCadastrou_id)=i.usuario_id and u.tipoAdmin = 'Normal' and u.email not like '%quintoandar%')
				then 'Organic Owner App'
				else 'Admin'
			end as acquisition_channel,
			case
				when (coalesce(i.originalUsuarioQueCadastrou_id, i.usuarioQueCadastrou_id)=i.usuario_id and u.tipoAdmin = 'Normal' and u.email not like '%quintoandar%')
				then 'Owner App'
				else 'Admin'
			end as acquisition_source
		from
			Imovel i
		left join
			ConversaoLead cl
			on cl.imovel_id = i.id
		left join
			Usuario u
			on u.id = coalesce(i.originalUsuarioQueCadastrou_id, i.usuarioQueCadastrou_id)
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
		and DATE(coalesce(i.dataCriacao, '1900-01-01 00:00:00')) <= DATE('{0}')
	union all
    select
     distinct
      i.id as imovel_id,
      l.id as lead_id,
      l.status as lead_status,
      l.lead_reason as lead_reason,
      l.reason,
      cl.id as conversao_id,
      case
        when rep.id is not null then rep.id
        when reg.dadosVendedor_id is not null then reg.id
        else null
      end as rep_id,
      uda.id as affiliate_id,
      i.usuario_id as owner_id,
      coalesce(i.regiao_id, l.region_id) as region_id,
      coalesce(l_aud_first_region.region_id, i.regiao_id) as first_region_id,
      coalesce(l.criadoEm, l.anuncioCriadoEm, l.captadoEm) as dt_lead,
      case
        when has_aud.id is not null then from_unixtime(ure.timestamp/1000)
        else coalesce(l.atualizadoEm, l.criadoEm) -- if there is no AUD records, we assume lead update or creation
      end as dt_prospect,
      fsc.dt as dt_first_contact,
      coalesce(cl.criadoEm, cl.dataConversao) as dt_conversion,
      case -- when excluded by specific reasons we count the lead as a qualified lead, even if its discarded
        when cl.leadConvertido_id is not null
          then coalesce(cl.criadoEm, cl.dataConversao, from_unixtime(ure.timestamp/1000))
        when l.lead_reason = 'ProprietarioRecusou' and l.reason != 'OWNER_DIDNT_LISTEN_TO_PITCH'
          then coalesce(from_unixtime(dure.timestamp/1000), from_unixtime(ure.timestamp/1000))
      end as dt_qualified,
      from_unixtime(dure.timestamp/1000) as dt_discarded,
      ure_disc.usuario_id as user_id_lead_first_discarder,
      ure_disc_max.usuario_id as user_id_lead_last_discarder,
      case
        when l.origem = 'OwnerPWA' then 'Self-Service Flow'
        else 'Lead Flow'
      end as flow,
      case
        when l.origem = 'OwnerPWA' then 'Self-Service'
        else 'Non-Self Service'
      end as acquisition_method,
      case
        when uda.id = 279289 and l.origem <> 'Reprocessado' then 'Doorman'
        when da.doormanAffiliateData_id is not null
            and dad.joinedProgramAt <= l.criadoEm
            and da.affiliateType = 'Doorman'
            then 'Doorman'
        when l.tipo = 'Porteiro' then 'Doorman'
        when l.tipo = 'Afiliado' and l.origem = 'App' then 'Affiliate App'
        when l.tipo = 'Afiliado' and l.origem = 'Form' then 'Affiliate Form'
        when l.tipo = 'Afiliado' and l.origem = 'Planilha' then 'Affiliate Spreadsheet'
        when l.tipo = 'Afiliado' and l.origem = 'Desconhecida' then 'Affiliate Unknown'
        when l.tipo = 'OpenLink' and l.origem = 'Landing' then 'Direct Referral'
        when l.origem = 'Facebook' then 'Facebook'
        when l.origem = 'Landing' then 'Landing Page Leads' -- BrokenOpenLink goes here also
        when l.origem = 'Crawling' then 'Crawling'
        when l.origem = 'OwnerPWA' and l.tipo = 'BrokenOpenLink' then 'Direct Referral'
        when l.origem = 'OwnerPWA' and l.tipo = 'LandingMarketing' then 'Landing Owner App'
        when l.origem = 'OwnerPWA' and l.tipo = 'LandingOpenLink' then 'Direct Referral'
        when l.origem = 'OwnerPWA' and l.tipo = 'Organic' then 'Organic Owner App'
        else 'Other'
      end as acquisition_channel,
      case
        when uda.id = 279289 and l.origem <> 'Reprocessado' then 'Doorman'
        when da.doormanAffiliateData_id is not null
            and dad.joinedProgramAt <= l.criadoEm
            and da.affiliateType = 'Doorman'
            then 'Doorman'
        when l.tipo = 'Porteiro' then 'Doorman'
        when l.origem = 'Reprocessado' then 'Reprocessed'
        when l.tipo = 'Afiliado' then 'Affiliate'
        when l.tipo = 'OpenLink' then 'Affiliate'
        when l.origem = 'Facebook' then 'Facebook'
        when l.origem = 'Landing' then 'Landing Page Leads' -- BrokenOpenLink goes here also
        when l.origem = 'Crawling' then 'Crawling'
        when l.origem = 'OwnerPWA' then 'Owner App'
        else 'Other'
      end as acquisition_source
    from
      (
        select
          le.*,
          coalesce(lr.reason, le.reason) as lead_reason
      from Lead le
      left join vw_lead_reason lr
      	on le.reason = lr.reason_detail
      where DATE(coalesce(criadoEm, '1900-01-01 00:00:00')) <= DATE('{0}') order by 1 asc
    ) l
    left join
      ConversaoLead cl
      on cl.leadConvertido_id = l.id
    left join
      Imovel i
      on i.id = cl.imovel_id
      AND DATE(coalesce(i.dataCriacao, '1900-01-01 00:00:00')) <= DATE('{0}')
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
        join
          UsuarioRevisionEntity ure on ure.id = la.REV
        where
          (status in ('Prospeccao','Descartado')
            and reason not in ('OWNER_WONT_ANSWER_PHONE','OWNER_DIDNT_ANSWER_PHONE','ProprietarioNaoAtende','ProprietarioNuncaAtende','CONTACT_DIDNT_EXIST')
            and not coalesce(la.automaticallyDiscarded, false))
          or status = 'Convertido'
        group by la.id
      ) fsc
      on fsc.id = l.id
    left join
      DadosAfiliado da
      on da.id = l.afiliadoQueIndicou_id
    left join
      DoormanAffiliateData dad
      on da.doormanAffiliateData_id = dad.id
    left join
      Usuario uda
      on uda.dadosAfiliado_id = da.id
    left join
      Usuario rep
      on rep.dadosVendedor_id = cl.vendedor_id
    left join
      Usuario reg
      on reg.id = coalesce(i.originalUsuarioQueCadastrou_id, i.usuarioQueCadastrou_id)
    left join
    (	SELECT
	    	laud.id,
	    	min(ure.id) as min_id
	    FROM Lead_AUD laud
	    join UsuarioRevisionEntity ure
	    	on laud.REV = ure.id
   		 where laud.status_MOD = 1
   		    and laud.status = 'Descartado'
                    and laud.automaticallyDiscarded = 0
    	group by laud.id
    ) d_ure
    	on d_ure.id = l.id
    left join
    	UsuarioRevisionEntity ure_disc
    	on ure_disc.id = d_ure.min_id
    left join (
		SELECT
	    	laud.id,
	    	max(ure.id) as max_id
	    FROM Lead_AUD laud
	    join UsuarioRevisionEntity ure
	    	on laud.REV = ure.id
   		 where laud.status = 'Descartado'
                    and laud.automaticallyDiscarded = 0
                    and (status_MOD + recurringStatusCount_MOD >= 1)
    	group by laud.id
    ) d_ure_max
        on d_ure_max.id = l.id
    left join
    	UsuarioRevisionEntity ure_disc_max
    	on ure_disc_max.id = d_ure_max.max_id
     left join (
		SELECT
	    	laud.id,
	    	min(laud.REV) as min_rev
	    FROM Lead_AUD laud
   		 where laud.region_id IS NOT NULL
    	group by laud.id
    ) first_rev_region
        on first_rev_region.id = l.id
    left join
    	Lead_AUD l_aud_first_region
    	on l_aud_first_region.REV = first_rev_region.min_rev
	union all
		select
			i.id as imovel_id,
			null as lead_id,
			null as lead_status,
			null as lead_reason,
			null as reason,
			cl.id as conversao_id,
			coalesce(i.originalUsuarioQueCadastrou_id, i.usuarioQueCadastrou_id) as rep_id,
			null as affiliate_id,
			i.usuario_id as owner_id,
			i.regiao_id as region_id,
			i.regiao_id as first_region_id,
			i.dataCriacao as dt_lead,
			i.dataCriacao as dt_prospect,
			coalesce(cl.criadoEm, cl.dataConversao) as dt_first_contact,
			coalesce(cl.criadoEm, cl.dataConversao) as dt_conversion,
			coalesce(cl.criadoEm, cl.dataConversao) as dt_qualified,
			null as dt_discarded,
			null as user_id_lead_first_discarder,
			null as user_id_lead_last_discarder,
			'Organic Flow' as flow,
			'Non-Self Service' as acquisition_method,
			'Inside Sales' as acquisition_channel,
			'Admin' as acquisition_source
		from
			ConversaoLead cl
		left join
			Imovel i
			on i.id = cl.imovel_id
			AND DATE(coalesce(i.dataCriacao, '1900-01-01 00:00:00')) <= DATE('{0}')
		left join
			Usuario u
			on u.id = coalesce(i.originalUsuarioQueCadastrou_id, i.usuarioQueCadastrou_id)
		where leadConvertido_id is null
	) base
	left join
		(select imovel_id, min(id) as id from JobFotografo group by imovel_id) first_job
		on base.imovel_id = first_job.imovel_id
	-- The following 3 joins are to identify if the first photo job was scheduled via self service
    left join
        (select id, min(REV) as REV from JobFotografo_AUD group by 1) first_rev_photo_job
        on first_job.id = first_rev_photo_job.id
    left join
        UsuarioRevisionEntity first_rev_photo_job_ure
            on first_rev_photo_job_ure.id = first_rev_photo_job.REV
    left join
        Usuario first_rev_photo_job_user
            on first_rev_photo_job_user.id = first_rev_photo_job_ure.usuario_id
            and first_rev_photo_job_user.dadosVendedor_id is null
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
		Lead l
		on l.id = base.lead_id
	left join
	(
		SELECT
            i.id,
            MIN(jaud.REV) as min_REV
        FROM Imovel i
        JOIN JobFotografo_AUD jaud
            ON i.id = jaud.imovel_id
            AND jaud.status_MOD = 1
            AND jaud.status = 'Agendado'
        JOIN UsuarioRevisionEntity ure
            ON ure.id = jaud.REV
            AND (i.firstPublication IS NULL  OR
                DATE(from_unixtime(ure.timestamp/1000)) <= DATE(i.firstPublication))
        JOIN Usuario u
            ON u.id = ure.usuario_id
            AND dadosVendedor_id IS NOT NULL
        GROUP BY 1
	) photo_rep_via_imovel
		on photo_rep_via_imovel.id = i.id
	left join	UsuarioRevisionEntity photo_rep_ure
	    on photo_rep_ure.id = photo_rep_via_imovel.min_REV
	CROSS JOIN (SELECT @cnt := 0) AS dummy
) tbl;
