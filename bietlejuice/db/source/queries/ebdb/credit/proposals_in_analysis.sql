select distinct
  t1.id as id_proposal,
  t1.proponente_id as id_proponent,
  t1.imovel_id as id_house,
  cast(concat(
    floor(timestampdiff(second,
                        case
                            when (case
                                    when t1.dataDocumentosEnviados >= t2.dataDocumentosEnviados
                                        then t1.dataDocumentosEnviados
                                    else t2.dataDocumentosEnviados
                                  end) >= t2.dataProposta
                                then (case
                                        when t1.dataDocumentosEnviados >= t2.dataDocumentosEnviados
                                            then t1.dataDocumentosEnviados
                                        else t2.dataDocumentosEnviados
                                      end)
                            else t2.dataProposta
                        end, now()) / 86400), ' days ',
    sec_to_time(round(timestampdiff(second,
                                    case
                                        when (case
                                                when t1.dataDocumentosEnviados >= t2.dataDocumentosEnviados
                                                    then t1.dataDocumentosEnviados
                                                else t2.dataDocumentosEnviados
                                              end) >= t2.dataProposta
                                            then (case
                                                    when t1.dataDocumentosEnviados >= t2.dataDocumentosEnviados
                                                        then t1.dataDocumentosEnviados
                                                    else t2.dataDocumentosEnviados
                                                  end)
                                        else t2.dataProposta
                                    end, now()) % 86400)), ' hours') as char) as last_interaction,
  '{sort_direction}' as sort_direction
from Proposta_AUD t1
join Proposta t2
    on t2.id = t1.id
where t1.expiresAt in (
    select max(expiresAt)
    from Proposta_AUD
    group by id
)
    and t1.statusDocumentacaoInq = 'Analise5a'
    and t1.status = 'EmAnalise'
    and t1.dataAprovacao is null
    and t1.inquilinoEnviouDocumentos = '1'
    and t1.expiresAt >= current_date
    and t1.id in (
        select id
        from Proposta
        where statusDocumentacaoInq = 'Analise5a'
            and status = 'EmAnalise'
    )
or t1.expiresAt in (
    select max(expiresAt)
    from Proposta_AUD
    group by id
)
    and t1.statusDocumentacaoInq = 'ReenvioDocumentos'
    and t1.status = 'EmAnalise'
    and t1.dataAprovacao is null
    and t1.expiresAt <= current_date
    and t1.id in (
        select id
        from Proposta
        where statusDocumentacaoInq = 'Analise5a'
            and status = 'EmAnalise'
    )
or t1.expiresAt in (
    select max(expiresAt)
    from Proposta_AUD
    group by id
)
    and t1.statusDocumentacaoInq = 'Analise5a'
    and t1.status = 'EmAnalise'
    and t1.dataAprovacao is null
    and t1.isTenantAutomaticSubmission = '1'
    and t1.inquilinoEnviouDocumentos ='0'
    and t1.expiresAt >= current_date
    and t1.id in (
        select id
        from Proposta
        where statusDocumentacaoInq = 'Analise5a'
            and status = 'EmAnalise'
    )
group by t1.id
order by last_interaction {sort_direction}
limit 10
;