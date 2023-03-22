WITH
revisions AS (
    SELECT
        p_aud.id_proposal,
        p_aud.tenant_documentation_status,
        p_aud.ts_documentation_sent,
        p_aud.mod_tenant_documentation_status,
        p_aud.rev,
        p_aud.status,
        p_aud.mod_status,
        p_aud.rejection_reason,
        p_aud.is_tenant_auto_submission,
        p_aud.guarantee,
        p_aud.mod_guarantee,
        ure.id,
        ure.ts_revision,
        ure.reason
    FROM datalake_ebdb_clean.proposal_aud p_aud
    JOIN datalake_ebdb_user.user_revision_entity ure
        ON p_aud.rev = ure.id
),
aud_analysis AS (
    SELECT
        r.id_proposal AS id_aud,
        -- It remains the same, AND thIS result should be the same AS the first date WHEN tenant_documentation_status = 'Analise5a'
        MIN(r.ts_documentation_sent) AS ts_tenant_first_doc_sent,
        COUNT(DISTINCT r.ts_documentation_sent) AS tenant_doc_sent_count,
        -- All columns related to credit analysIS should be considered deprecated after 2020-08-06
        MIN(
          CASE WHEN r.ts_revision < date('2020-01-02')
              THEN IF(r.tenant_documentation_status = 'AnaliseCredito', r.ts_revision, NULL)
                  ELSE IF(r.tenant_documentation_status = 'Analise5a', r.ts_revision, NULL)
          END
        ) AS ts_credit_analysis_first_init,
        MAX(
          CASE WHEN r.ts_revision < date('2020-01-02')
              THEN IF(r.tenant_documentation_status = 'AnaliseCredito', r.ts_revision, NULL)
                  ELSE IF(r.tenant_documentation_status = 'Analise5a', r.ts_revision, NULL)
          END
        ) AS ts_credit_analysis_last_init,
        MIN(IF(r.tenant_documentation_status in ('Aprovado', 'RecusadoCredito', 'StandBy'), r.ts_revision, NULL)) AS ts_credit_analysis_first_end,
        MAX(IF(r.tenant_documentation_status in ('Aprovado', 'RecusadoCredito', 'StandBy'), r.ts_revision, NULL)) AS ts_credit_analysis_last_end,
        MAX(IF(r.tenant_documentation_status = 'Aprovado', r.ts_revision, NULL)) AS ts_credit_approved_last,
        MIN(IF(r.tenant_documentation_status = 'AnaliseCredito', r.ts_revision, NULL)) AS ts_tenant_first_doc_complete,
        MAX(IF(r.tenant_documentation_status = 'AnaliseCredito', r.ts_revision, NULL)) AS ts_tenant_last_doc_complete,
        MAX(COALESCE(r.is_tenant_auto_submission, false)) AS is_doc_reused,
        MIN(r.ts_revision) AS added_rev_doc_row,
        MIN(
          CASE WHEN r.ts_revision > date('2020-06-07')
              THEN IF(r.tenant_documentation_status = 'AnaliseCredito', r.ts_revision, NULL)
          END
        ) AS ts_credit_evaluation_first_init,
        MAX(
          CASE WHEN r.ts_revision > date('2020-06-07')
              THEN IF(r.tenant_documentation_status = 'AnaliseCredito', r.ts_revision, NULL)
          END
        ) AS ts_credit_evaluation_last_init,
        MIN(
          CASE WHEN r.ts_revision > date('2020-06-07')
              THEN IF(r.tenant_documentation_status = 'RecusadoCredito' AND r.rejection_reason = 'CreditEvaluationRejected', r.ts_revision, NULL)
          END
        ) AS ts_credit_evaluation_first_negative,
        MAX(
          CASE WHEN r.ts_revision > date('2020-06-07')
              THEN IF(r.tenant_documentation_status = 'RecusadoCredito' AND r.rejection_reason = 'CreditEvaluationRejected', r.ts_revision, NULL)
          END
        ) AS ts_credit_evaluation_last_negative,
        MIN(
         CASE WHEN r.ts_revision > date('2020-06-07')
             THEN IF(r.tenant_documentation_status = 'Aprovado', r.ts_revision, NULL)
         END
        ) AS ts_doc_analysis_first_approved,
        MAX(
         CASE WHEN r.ts_revision > date('2020-06-07')
            THEN IF(r.tenant_documentation_status = 'Aprovado', r.ts_revision, NULL)
         END
        ) AS ts_doc_analysis_last_approved,
        MIN(
         CASE WHEN r.ts_revision > date('2020-06-07')
            THEN IF(r.tenant_documentation_status = 'RecusadoCredito' AND r.rejection_reason = 'TenantDocumentationRejected', r.ts_revision, NULL)
         END
        ) AS ts_doc_analysis_first_rejected,
        MAX(
         CASE WHEN r.ts_revision > date('2020-06-07')
            THEN IF(r.tenant_documentation_status = 'RecusadoCredito' AND r.rejection_reason = 'TenantDocumentationRejected', r.ts_revision, NULL)
         END
        ) AS ts_doc_analysis_last_rejected
    FROM revisions r
    WHERE r.mod_tenant_documentation_status AND r.tenant_documentation_status != 'NaoEnviado'
    GROUP BY r.id_proposal
),
aud_status AS (
    SELECT
        r.id_proposal AS id_aud,
        MAX(r.ts_revision) AS ts_processed
    FROM revisions r
    WHERE r.mod_status AND r.status in ('Aprovada', 'Rejeitada')
    GROUP BY 1
),
aud_guarantee AS (
    SELECT
        r.id_proposal AS id_aud,
        MIN(r.ts_revision) AS ts_processed
    FROM revisions r
    WHERE
      r.mod_guarantee
      AND r.guarantee = 'RentalGuarantee'
    GROUP BY 1
), 

folder_proposal AS (
SELECT 
    id_source_folder, -- each folder for a proponent
    id,  -- still a user grain
    MAX(get_json_object(reference_properties, '$.proposalId')) id_proposal
FROM datalake_docx_clean.folder_reference fr 
WHERE id_folder_reference_type = 7
GROUP BY 1,2
), 

aud_folder_reference AS (
SELECT 
    fp.id_proposal,
    COUNT(DISTINCT ts_documentation_sent) doc_postings,
    MIN(ts_documentation_sent) ts_first_doc_sent
FROM datalake_docx_clean.folder_reference_aud fra 
JOIN folder_proposal fp ON fp.id = fra.id
GROUP BY 1
), 

auto_document AS (
SELECT DISTINCT 
    id_proposal 
FROM datalake_docx_clean.document_aud da 
JOIN folder_proposal fp ON fp.id_source_folder = da.id_folder AND fp.id_proposal = da.id_context_external
WHERE true 
    AND rev_type = 0 
    AND attributes IS NULL
    AND id_document_context = 2 
)

SELECT
    p.id,
    p.id_pre_proposal,
    ch.id_COUNTry,
    p.id_offer,
    COALESCE(ch.country_code, 'Undefined') AS country_code,
    p.guarantee,
    cap.income,
    cap.last_result,
    p.motivation,
    p.rent_proposal,
    p.status,
    cap.status AS status_sorting_hat,
    p.tenant_documentation_status,
    p.owner_documentation_status,
    cap.package,
    p.rejection_reason,
    cap.dti,
    cap.number_evaluations,
    COALESCE(cap.Risk_Category_Canon, cap.Risk_Category_Canon_past_filler) AS risk_category_canon,
    cap.risk_category,
    COALESCE(afr.doc_postings, aud_analysis.tenant_doc_sent_COUNT) AS tenant_doc_sent_count_docx,   --- check IF valid
    aud_analysis.tenant_doc_sent_count,
    p.has_tenant_sent_documentation,
    p.has_owner_sent_documentation,
    p.has_tenant_accepted_contract,
    p.has_owner_accepted_contract,
    p.has_additive_term,
    COALESCE(IF(ad.id_proposal IS NOT NULL,TRUE,NULL) ,COALESCE(aud_analysis.is_doc_reused, FALSE)) AS is_doc_reused,
    p.ts_to_scheduling,
    p.ts_proposal,
    p.ts_approved,
    p.ts_documentation_sent,
    p.ts_owner_documentation_sent,
    aud_status.ts_processed,
    p.ts_created,
    p.ts_updated,
    aud_analysis.ts_tenant_first_doc_sent,
    IF(aud_analysis.is_doc_reused, aud_analysis.added_rev_doc_row, NULL) AS ts_tenant_auto_first_doc_sent,
    aud_analysis.ts_tenant_first_doc_complete,
    aud_analysis.ts_tenant_last_doc_complete,
    -- Dates related to credit analysIS (these dates had their business rules changed ON jan/2020 AND are deprecated after 08/06/2020).
    aud_analysis.ts_credit_analysis_first_init,
    aud_analysis.ts_credit_analysis_last_init AS dt_credit_analysis_last_init,  -- Column to match ODS rules
    CASE
        WHEN CAST(p.ts_created AS DATE) < DATE('2020-01-02') THEN COALESCE(cap.ts_first_analyzed, aud_analysis.ts_credit_analysis_last_init)
        ELSE aud_analysis.ts_credit_analysis_last_init
    END AS ts_credit_analysis_last_init,
    aud_analysis.ts_credit_analysis_first_end,
    aud_analysis.ts_credit_analysis_last_end AS dt_credit_analysis_last_end,
    CASE
        WHEN CAST(p.ts_created AS DATE) < DATE('2020-01-02') THEN COALESCE(cap.ts_processed, aud_analysis.ts_credit_analysis_last_end, cap.ts_analyzed)
        ELSE aud_analysis.ts_credit_analysis_last_end
    END AS ts_credit_analysis_last_end,
    aud_analysis.ts_credit_approved_last,

    aud_analysis.ts_credit_evaluation_first_init,
    aud_analysis.ts_credit_evaluation_last_init,
    aud_analysis.ts_credit_evaluation_first_negative,
    aud_analysis.ts_credit_evaluation_last_negative,
    COALESCE(cap.ts_last_credit_evaluation_positive, 
      IF(aud_analysis.ts_credit_evaluation_last_negative IS NOT NULL 
        AND COALESCE(cap.rental_guarantee_category, cap.last_category) IS NOT NULL
        , aud_analysis.ts_credit_evaluation_last_negative, NULL)) AS ts_automatic_model_evaluation_positive,
    COALESCE(cap.ts_last_credit_evaluation_positive, cap.ts_paid_guarantee_created) ts_guarantee_chosen, 
    COALESCE(ts_tenant_first_doc_sent, IF(aud_analysis.is_doc_reused, aud_analysis.added_rev_doc_row, NULL)) ts_tenant_first_document_sent,
    afr.ts_first_doc_sent AS ts_docx_first_doc_sent,
    COALESCE(cap.ts_guarantee_paid, aud_analysis.ts_credit_approved_last) ts_guarantee_validated,

    aud_guarantee.ts_processed AS ts_guarantee,
    aud_analysis.ts_doc_analysis_first_approved,
    aud_analysis.ts_doc_analysis_last_approved,
    aud_analysis.ts_doc_analysis_first_rejected,
    aud_analysis.ts_doc_analysis_last_rejected,
    cap.ts_first_credit_evaluation_positive,
    cap.ts_guarantee_paid,
    cap.ts_last_credit_evaluation_positive,
    p.ts_entrance,
    CASE
       WHEN cap.guarantee_source = 'CRM_DOCUMENTATION_ANALYSIS' THEN TRUE
       ELSE FALSE
    END AS is_guarantee_FROM_crm,
    cap.is_retenant
FROM
    datalake_ebdb_clean.proposal AS p
LEFT JOIN
    aud_analysis
        ON aud_analysis.id_aud = p.id
LEFT JOIN
    aud_status
        ON aud_status.id_aud = p.id
LEFT JOIN
    aud_guarantee
        ON aud_guarantee.id_aud = p.id
LEFT JOIN
    datalake_credit_analysis.credit_analysis_proposals AS cap
        ON p.id = cap.id_proposal
LEFT JOIN
    datalake_ebdb_country.house AS ch
        ON ch.id_house = p.id_house
LEFT JOIN 
    aud_folder_reference afr
        ON afr.id_proposal = p.id
LEFT JOIN 
    auto_document ad 
        ON ad.id_proposal = p.id