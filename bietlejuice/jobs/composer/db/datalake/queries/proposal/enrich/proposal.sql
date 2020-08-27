with
revisions as (
    select
        p_aud.id_proposal,
        p_aud.tenant_documentation_status,
        p_aud.ts_documentation_sent,
        p_aud.mod_tenant_documentation_status,
        p_aud.rev,
        p_aud.status,
        p_aud.mod_status,
        p_aud.rejection_reason,
        ure.id,
        cast(from_unixtime(ure.ts_revision/1000) as timestamp) as ts_revision,
        ure.reason
    from datalake_ebdb_clean.proposal_aud p_aud
    join datalake_ebdb_clean.user_revision_entity ure
        on p_aud.rev = ure.id
),
aud_analysis as (
    select
        r.id_proposal as id_aud,
        -- It remains the same, and this result should be the same as the first date when tenant_documentation_status = 'Analise5a'
        min(r.ts_documentation_sent) as ts_tenant_first_doc_sent,
        count(distinct r.ts_documentation_sent) as tenant_doc_sent_count,
        -- All columns related to credit analysis should be considered deprecated after 2020-08-06
        min(
          case when r.ts_revision < date('2020-01-02')
              then if(r.tenant_documentation_status = 'AnaliseCredito', r.ts_revision, null)
                  else if(r.tenant_documentation_status = 'Analise5a', r.ts_revision, null)
          end
        ) as ts_credit_analysis_first_init,
        max(
          case when r.ts_revision < date('2020-01-02')
              then if(r.tenant_documentation_status = 'AnaliseCredito', r.ts_revision, null)
                  else if(r.tenant_documentation_status = 'Analise5a', r.ts_revision, null)
          end
        ) as ts_credit_analysis_last_init,
        min(if(r.tenant_documentation_status in ('Aprovado', 'RecusadoCredito', 'StandBy'), r.ts_revision, null)) as ts_credit_analysis_first_end,
        max(if(r.tenant_documentation_status in ('Aprovado', 'RecusadoCredito', 'StandBy'), r.ts_revision, null)) as ts_credit_analysis_last_end,
        max(if(r.tenant_documentation_status = 'Aprovado', r.ts_revision, null)) as ts_credit_approved_last,
        min(if(r.tenant_documentation_status = 'AnaliseCredito', r.ts_revision, null)) as ts_tenant_first_doc_complete,
        max(if(r.tenant_documentation_status = 'AnaliseCredito', r.ts_revision, null)) as ts_tenant_last_doc_complete,
        if(date_format(min(r.ts_revision), 'yyyy-MM-dd HH:mm:ss') != date_format(min(r.ts_documentation_sent), 'yyyy-MM-dd HH:mm:ss'),
             max(r.reason is null or r.reason like '[AUTO] used previous tenant%'), false) as is_doc_reused,
        min(r.ts_revision) as added_rev_doc_row,
        min(
          case when r.ts_revision > date('2020-06-07')
              then if(r.tenant_documentation_status = 'AnaliseCredito', r.ts_revision, null)
          end
        ) as ts_credit_evaluation_first_init,
        max(
          case when r.ts_revision > date('2020-06-07')
              then if(r.tenant_documentation_status = 'AnaliseCredito', r.ts_revision, null)
          end
        ) as ts_credit_evaluation_last_init,
        min(
          case when r.ts_revision > date('2020-06-07')
              then if(r.tenant_documentation_status = 'RecusadoCredito' and r.rejection_reason = 'CreditEvaluationRejected', r.ts_revision, null)
          end
        ) as ts_credit_evaluation_first_negative,
        max(
          case when r.ts_revision > date('2020-06-07')
              then if(r.tenant_documentation_status = 'RecusadoCredito' and r.rejection_reason = 'CreditEvaluationRejected', r.ts_revision, null)
          end
        ) as ts_credit_evaluation_last_negative,
        min(
         case when r.ts_revision > date('2020-06-07')
             then if(r.tenant_documentation_status = 'Aprovado', r.ts_revision, null)
         end
        ) as ts_doc_analysis_first_approved,
        max(
         case when r.ts_revision > date('2020-06-07')
            then if(r.tenant_documentation_status = 'Aprovado', r.ts_revision, null)
         end
        ) as ts_doc_analysis_last_approved,
        min(
         case when r.ts_revision > date('2020-06-07')
            then if(r.tenant_documentation_status = 'RecusadoCredito' and r.rejection_reason = 'TenantDocumentationRejected', r.ts_revision, null)
         end
        ) as ts_doc_analysis_first_rejected,
        max(
         case when r.ts_revision > date('2020-06-07')
            then if(r.tenant_documentation_status = 'RecusadoCredito' and r.rejection_reason = 'TenantDocumentationRejected', r.ts_revision, null)
         end
        ) as ts_doc_analysis_last_rejected
    from revisions r
    where r.mod_tenant_documentation_status and r.tenant_documentation_status != 'NaoEnviado'
    group by r.id_proposal
),
aud_status as (
    select
        r.id_proposal as id_aud,
        max(r.ts_revision) as ts_processed
    from revisions r
    where r.mod_status and r.status in ('Aprovada', 'Rejeitada')
    group by 1
),
sortinghat_proposal as (
    with sortinghat_proposal_prev as (
        select
            p.id,
            p.ts_analyzed,
            p.status,
            p.ts_processed,
            pv.ts_analyzed as ts_analyzed_version,
            row_number() over (partition by p.id order by pv.id) as rn
        from datalake_sorting_hat_clean.proposal p
        left join datalake_sorting_hat_clean.proposal_version pv
            on p.id = pv.id_proposal
    )
    select
        id,
        ts_analyzed,
        status,
        ts_processed,
        coalesce(ts_analyzed_version, ts_analyzed) as ts_first_analyzed
    from sortinghat_proposal_prev
    where rn = 1
)
select
    p.id,
    p.id_pre_proposal,
    p.id_offer,
    p.guarantee,
    p.motivation,
    p.rent_proposal,
    p.status,
    shp.status as status_sorting_hat,
    p.tenant_documentation_status,
    p.owner_documentation_status,
    p.rejection_reason,
    aud_analysis.tenant_doc_sent_count,
    p.has_tenant_sent_documentation,
    p.has_owner_sent_documentation,
    p.has_tenant_accepted_contract,
    p.has_owner_accepted_contract,
    p.has_additive_term,
    coalesce(aud_analysis.is_doc_reused, false) as is_doc_reused,
    p.ts_to_scheduling,
    p.ts_proposal,
    p.ts_approved,
    p.ts_documentation_sent,
    p.ts_owner_documentation_sent,
    aud_status.ts_processed,
    p.ts_created,
    p.ts_updated,
    aud_analysis.ts_tenant_first_doc_sent,
    if(aud_analysis.is_doc_reused, aud_analysis.added_rev_doc_row, null) as ts_tenant_auto_first_doc_sent,
    aud_analysis.ts_tenant_first_doc_complete,
    aud_analysis.ts_tenant_last_doc_complete,
    -- Dates related to credit analysis (these dates had their business rules changed on jan/2020 and are deprecated after 08/06/2020).
    aud_analysis.ts_credit_analysis_first_init,
    case when cast(p.ts_created as date) < date('2020-01-02')
        then coalesce(shp.ts_first_analyzed, aud_analysis.ts_credit_analysis_last_init)
        else aud_analysis.ts_credit_analysis_last_init
    end as ts_credit_analysis_last_init,
    aud_analysis.ts_credit_analysis_first_end,
    case when cast(p.ts_created as date) < date('2020-01-02')
        then coalesce(shp.ts_processed, aud_analysis.ts_credit_analysis_last_end, shp.ts_analyzed)
        else aud_analysis.ts_credit_analysis_last_end
    end as ts_credit_analysis_last_end,
    aud_analysis.ts_credit_approved_last,
    aud_analysis.ts_credit_evaluation_first_init,
    aud_analysis.ts_credit_evaluation_last_init,
    aud_analysis.ts_credit_evaluation_first_negative,
    aud_analysis.ts_credit_evaluation_last_negative,
    aud_analysis.ts_doc_analysis_first_approved,
    aud_analysis.ts_doc_analysis_last_approved,
    aud_analysis.ts_doc_analysis_first_rejected,
    aud_analysis.ts_doc_analysis_last_rejected
from datalake_ebdb_clean.proposal p
left join aud_analysis
    on aud_analysis.id_aud = p.id
left join aud_status
    on aud_status.id_aud = p.id
left join sortinghat_proposal shp
        on shp.id = p.id