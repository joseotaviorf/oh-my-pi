select
      f.id,
      f.imovel_id,
      f.status as job_status,
      case
        when creator.dadosFotografo_id is not null and creator.dadosVendedor_id is not null then 'Teste'
        when creator.dadosFotografo_id is not null then 'Fotografo'
        when creator.dadosVendedor_id is not null then 'InsideSales_internal'
        when creator.email like ('%actionline%') then 'InsideSales_external'
        when creator.email like ('%quintoandar%') then 'Admin'
        else 'Prop'
      end as creation_origin,
      case
        when hour(f.dataAgendamento) between 6 and 23 or f.dataAgendamento is null
        then 0
        else 1
      end as flexible_schedule,
      -- same_day_upload applies to any upload until 8 AM (5AM - due to UTC diff) of the next day after the photo shoot
      coalesce((f.dataUploadFotos <= date(coalesce(f.dataInicioSessao, f.dataAgendamento)) + interval '1' day + interval '8' hour), false) as same_day_upload,
      -- job_on_time applies to any upload until 8 AM (5AM - due to UTC diff) of the next day after the photo shoot scheduled date
      coalesce((f.dataUploadFotos <= date(f.dataAgendamento) + interval '1' day + interval '8' hour), false) as job_on_time,
      -- job anticipated applies to any photo job uploaded on D-1 or earlier in relation to its scheduled date
      coalesce((date_format(f.dataUploadFotos,'%Y-%m-%d') < date_format(date(f.dataAgendamento),'%Y-%m-%d')), false) as job_anticipated,
      f.dataAceitoFotografo as dt_photographer_accepted,
      f.dataCriacao as dt_job_created,
      f.dataJobPedido as dt_job_issued,
      f.dataInicioSessao as dt_shoot_started,
      f.dataAgendamento as dt_job_scheduled,
      f.dataUploadFotos as dt_photos_uploaded,
      f.atualizadoEm as dt_updated,
      FROM_UNIXTIME(ureP.timestamp/1000) as dt_problem_reported,
      f.instrucoesAgendamento as scheduling_instructions,
      f.nomeContatoSessaoFotos as photo_shoot_contact_name,
      f.emailSessaoFotos as photo_shoot_email,
      f.telefoneSessaoFotos as photo_shoot_phone,
      f.telefoneSessaoFotosSecundario as photo_shoot_second_phone,
      f.aprovado+0 as approved,
      f.confirmado+0 as confirmed,
      f.lockbox+0 as lockbox,
      f.retirarChave as key_withdraw,
      f.outrosChave as key_comments,
      af.id as photographer_id,
      af.nome as photographer_name,
      af.email as photographer_email,
      df.criadoEm as dt_photographer_start,
      f.tipoContrato as photographer_contract_type,
      f.problema as photographer_problem_reason,
      f.photoSender as user_sender_type,
      coalesce(f.motivoAlteracao, h.photoShootSchedulingReason) as cancel_reason,
      f.textoMotivoCancelamento as cancel_reason_detailed,
      FROM_UNIXTIME(ure.timestamp/1000) as user_cancel_dt,
      uc.id as user_cancel_id,
      uc.nome as user_cancel_name,
      uc.email as user_cancel_email,
      case
        when  f.status != 'Cancelado' then null
        when uc.dadosFotografo_id is not null and uc.dadosVendedor_id is not null then 'Teste'
        when uc.dadosFotografo_id is not null then 'Fotografo'
        when creator.dadosVendedor_id is not null then 'InsideSales_internal'
        when creator.email like ('%actionline%') then 'InsideSales_external'
        when uc.email like ('%quintoandar%') then 'Admin'
        when ure.id is null then null
        else 'Prop'
      end as user_cancel_type,
      case
        when creator.dadosVendedor_id is not null then creator.id
        else null
      end as rep_id,
      TIMESTAMPDIFF(
        MINUTE,
        f.dataCriacao,
        case
          when hour(f.dataAgendamento) between 6 and 23 then f.dataAgendamento
          when date(f.dataAgendamento) + interval '12' hour < f.dataCriacao then f.dataCriacao
        else date(f.dataAgendamento) + interval '12' hour end
      ) as creation_to_scheduling_diff_minutes,
      round(TIMESTAMPDIFF(
        MINUTE,
        f.dataCriacao,
        case
          when hour(f.dataAgendamento) between 6 and 23 then f.dataAgendamento
          when date(f.dataAgendamento) + interval '12' hour < f.dataCriacao then f.dataCriacao
        else date(f.dataAgendamento) + interval '12' hour end
      )/60,1) as creation_to_scheduling_diff_hours,
      round(TIMESTAMPDIFF(
        MINUTE,
        f.dataCriacao,
        case
          when hour(f.dataAgendamento) between 6 and 23 then f.dataAgendamento
          when date(f.dataAgendamento) + interval '12' hour < f.dataCriacao then f.dataCriacao
        else date(f.dataAgendamento) + interval '12' hour end
      )/1440,1) as creation_to_scheduling_days
    from JobFotografo f
    left join
        (select id, max(REV) as REV from JobFotografo_AUD where status in ('Cancelado') and status_MOD = 1 group by id) f_cancel_revision
        on f_cancel_revision.id = f.id
        and f.status in ('Cancelado')
    left join
        (select id, max(REV) as REV from JobFotografo_AUD where status in ('ComProblema') and status_MOD = 1 group by id) f_problem_revision
        on f_problem_revision.id = f.id
    left join UsuarioRevisionEntity ure on ure.id = f_cancel_revision.REV
    left join UsuarioRevisionEntity ureP on ureP.id = f_problem_revision.REV
    left join Usuario uc on uc.id = ure.usuario_id
    left join Usuario af on af.dadosFotografo_id = f.dadosFotografo_id
    left join DadosFotografo df on df.id = f.dadosFotografo_id
    left join
      (select id, min(REV) as REV from JobFotografo_AUD group by id) min_j
      on min_j.id = f.id
    left join UsuarioRevisionEntity ure2 on ure2.id = min_j.REV
    left join Usuario creator on creator.id = ure2.usuario_id
    left join
    (
      SELECT
        hrs_aud.photoShoot_id,
        MAX(REV) as rev
      FROM HouseRegistrationStatus_AUD hrs_aud
      GROUP BY hrs_aud.photoShoot_id
    ) rev on rev.photoShoot_id = f.id
    left join HouseRegistrationStatus_AUD h on h.REV = rev.rev
where DATE(coalesce(f.dataCriacao, '1900-01-01 00:00:00')) <= DATE('{}')
