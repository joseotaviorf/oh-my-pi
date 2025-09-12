WITH resend_events AS
    (
        SELECT
            DATE_TRUNC('day', DATE_ADD(FROM_UNIXTIME(ts_revision / 1000), -3)) AS dt_resend_requested,
            COUNT(*) AS resend_count
        FROM datalake_ebdb_clean.proposal_aud AS p
            INNER JOIN datalake_ebdb_clean.user_revision_entity AS u
            ON p.rev = u.id
            INNER JOIN datalake_ebdb_clean.user AS us
            ON u.id_user = us.id
            LEFT JOIN dw_rent.fact_listing_rent_flows AS f ON
            p.id_proposal = f.sk_proposal
            LEFT JOIN dw_rent.dim_house_listing AS hl
            ON f.sk_house_listing = hl.sk_house_listing
        WHERE p.tenant_documentation_status = 'ReenvioDocumentos'
            AND p.mod_tenant_documentation_status = TRUE
            AND hl.country_code == 'BR' GROUP  BY 1
    ),
    first_docs_sent AS (
        SELECT
            TO_DATE(NULLIF(f.sk_tenant_first_doc_sent_date, -1), 'yyyyMMdd') AS dt_doc_sent,
            COUNT(f.sk_proposal) AS first_doc_sent_count
        FROM dw_rent.fact_listing_rent_flows f
            LEFT JOIN dw_rent.dim_house_listing AS hl
            ON f.sk_house_listing = hl.sk_house_listing
        WHERE hl.country_code == 'BR' GROUP  BY 1
    ),
    last_3_months AS (
        SELECT
            DATE_TRUNC('month', dd.date) AS MONTH,
            SUM(r.resend_count) AS resend_count,
            SUM(ds.first_doc_sent_count) AS first_doc_sent_count
        FROM dw_public.dim_date AS dd
            LEFT JOIN resend_events AS r
            ON dd.date = r.dt_resend_requested
            LEFT JOIN first_docs_sent AS ds
            ON dd.date = ds.dt_doc_sent
        WHERE ds.dt_doc_sent >= DATE_TRUNC('MM', ADD_MONTHS(CURRENT_DATE(), -3))
            AND ds.dt_doc_sent < DATE_TRUNC('MM', CURRENT_DATE())
        GROUP  BY 1
    ),
population_data AS (
SELECT
      AVG(first_doc_sent_count) AS first_doc_sent_avg,
      AVG(resend_count) AS resend_avg
  FROM last_3_months
),
guarantee AS (
    SELECT
        id_proposal,
        type,
        result,
        reason,
        ts_updated,
        ROW_NUMBER() OVER (PARTITION BY id_proposal
                            ORDER BY ts_updated DESC) AS rn
    FROM datalake_sorting_hat_clean.credit_analysis_version
),
analysts AS (
    SELECT
        CAST(ar.id_external AS INTEGER) AS id_proposal,
        ci.input_source_name AS analyst
    FROM datalake_sorting_hat_clean.analysis_request ar
    INNER JOIN datalake_sorting_hat_clean.checklist c
    ON c.id_analysis_request = ar.id
    INNER JOIN datalake_sorting_hat_clean.checklist_group cg
    ON cg.id_checklist = c.id
    INNER JOIN datalake_sorting_hat_clean.checklist_item ci
    ON ci.id_checklist_group = cg.id
    WHERE is_current_checklist
        AND input_type = 'MANUAL'
    GROUP BY 1, 2
),
latest_week_analyses AS (
  SELECT
      g.id_proposal,
      g.type,
      g.ts_updated AS ts_credit_analysis_updated,
      g.result,
      g.reason,
      analyst
  FROM guarantee g
  LEFT JOIN analysts
  ON analysts.id_proposal = g.id_proposal
  WHERE g.rn = 1
      AND g.ts_updated >= DATE_TRUNC('week', NOW()) - INTERVAL '1 week'
      AND g.ts_updated < DATE_TRUNC('week', NOW())
      AND result NOT IN ('NEW',
                          'ADVISABLE',
                          'INADVISABLE')
      AND analyst IS NOT NULL
  ORDER BY ts_updated ASC
),
constants_calculator AS (
  SELECT
    2.58 AS z_score,
    0.055 AS error,
    0.5 AS population_proportion,
    1.4 AS resend_multiplication_factor,
    30 AS days_in_month,
    7 AS days_in_week
),
calculated_factors AS (
  SELECT
    p.first_doc_sent_avg,
    p.resend_avg,
    p.resend_avg / P.first_doc_sent_avg AS resend_share,
    POWER(c.z_score, 2) AS z_squared,
    POWER(c.error, 2) AS error_squared,
    c.population_proportion * (1 - C.population_proportion) AS population_proportion_factor,
    c.resend_multiplication_factor,
    c.days_in_month,
    c.days_in_week
  FROM
    population_data AS p,
    constants_calculator AS c
),
intermediate_calculations AS (
  SELECT
    days_in_month,
    days_in_week,
    z_squared * population_proportion_factor / error_squared AS infinite_pop_sample_size,
    resend_multiplication_factor * (1 - resend_share) AS resent_docs_adj_factor,
    (z_squared * population_proportion_factor) / (error_squared * first_doc_sent_avg) AS finite_pop_factor
  FROM
    calculated_factors
),
weekly_sample_size AS (
  SELECT
      ROUND(
          (
              (resent_docs_adj_factor * infinite_pop_sample_size / (1 + finite_pop_factor)) / days_in_month
          ) * days_in_week
      ) AS weekly_sample_size
  FROM
      intermediate_calculations
),
grouped_analysis AS (
    SELECT
        *,
        COUNT(*) OVER () AS total_population_size,
        COUNT(*) OVER (PARTITION BY analyst, type) AS group_size_before_sampling
    FROM
        latest_week_analyses
),
samples_per_group AS (
    SELECT DISTINCT
        ga.analyst,
        ga.type,
        GREATEST(
            ROUND(
                ga.group_size_before_sampling / (SELECT total_population_size FROM grouped_analysis LIMIT 1) * wss.weekly_sample_size
            ),
            1
        ) AS num_samples_for_group
    FROM
        grouped_analysis AS ga,
        weekly_sample_size AS wss
),
proportional_samples_raw AS (
    SELECT
        id_proposal,
        type,
        ts_credit_analysis_updated,
        result,
        reason,
        analyst,
        ROW_NUMBER() OVER (PARTITION BY ga.analyst, ga.type ORDER BY RAND()) AS rn
    FROM
        grouped_analysis AS ga
),
proportional_samples AS (
    SELECT
        psr.id_proposal,
        psr.type,
        psr.ts_credit_analysis_updated,
        psr.result,
        psr.reason,
        psr.analyst
    FROM
        proportional_samples_raw AS psr
    JOIN samples_per_group AS spg
        ON psr.analyst = spg.analyst AND psr.type = spg.type
    WHERE
        psr.rn <= spg.num_samples_for_group
),
one_rejection_per_analyst AS (
    SELECT
        id_proposal,
        type,
        ts_credit_analysis_updated,
        result,
        reason,
        analyst
    FROM
        latest_week_analyses
    WHERE
        result = 'REJECTED'
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY analyst ORDER BY RAND()) = 1
),
missing_rejections AS (
    SELECT
        ora.id_proposal,
        ora.type,
        ora.ts_credit_analysis_updated,
        ora.result,
        ora.reason,
        ora.analyst
    FROM
        one_rejection_per_analyst AS ora
    LEFT JOIN proportional_samples AS ps
        ON ora.analyst = ps.analyst AND ps.result = 'REJECTED'
    WHERE
        ps.analyst IS NULL
),
credit_audit_sample AS (
  SELECT DISTINCT
    *
  FROM
    proportional_samples
  UNION ALL
  SELECT DISTINCT
    *
  FROM
    missing_rejections
),
filtered_documents AS (
  SELECT
    d.id AS document_id,
    attributes,
    d.ts_updated AS document_ts_updated,
    id_folder,
    id_document_type,
    reference_properties,
    id_context_external
  FROM
    datalake_docx_clean.document AS d
    INNER JOIN datalake_docx_clean.folder_reference AS fr ON d.id_folder = fr.id_source_folder
  WHERE
    id_folder IS NOT NULL
    AND id_folder_reference_type = 7
),
id_document_processed AS (
  SELECT
    document_id AS id,
    GET_JSON_OBJECT(attributes, '$.fullName') AS name,
    id_folder,
    document_ts_updated AS ts_updated
  FROM
    filtered_documents
  WHERE
    id_document_type = 7
),
id_document_deduped AS (
  SELECT
    id,
    name,
    id_folder
  FROM
    id_document_processed
  QUALIFY
    ROW_NUMBER() OVER (
      PARTITION BY id
      ORDER BY ts_updated DESC
    ) = 1
),
income_document_processed AS (
  SELECT
    document_id AS id,
    GET_JSON_OBJECT(attributes, '$.incomeNature.bankStatements') AS statements_json_str,
    GET_JSON_OBJECT(attributes, '$.incomeNature.payslips') AS payslips_json_str,
    GET_JSON_OBJECT(reference_properties, '$.proposalId') AS id_proposal,
    GET_JSON_OBJECT(reference_properties, '$.proposalProponentId') AS id_proponent,
    id_folder,
    id_context_external,
    document_ts_updated AS ts_updated
  FROM
    filtered_documents
  WHERE
    id_document_type = 11
),
income_document_deduped AS (
  SELECT
    id,
    id_proposal,
    id_folder,
    id_context_external,
    id_proponent,
    statements_json_str,
    payslips_json_str
  FROM
      income_document_processed
  QUALIFY
    ROW_NUMBER() OVER (
      PARTITION BY id_proposal, id_proponent
      ORDER BY ts_updated DESC
    ) = 1
),
income_document_joined AS (
  SELECT
    ide.id,
    ide.id_proposal,
    ide.id_folder,
    ide.id_context_external,
    ide.id_proponent,
    ide.statements_json_str,
    ide.payslips_json_str,
    cas.type,
    cas.ts_credit_analysis_updated,
    cas.result,
    cas.reason,
    cas.analyst
  FROM
    credit_audit_sample AS cas
    LEFT JOIN income_document_deduped AS ide ON ide.id_proposal = cas.id_proposal
),
data_joined AS (
  SELECT
    idj.id_proposal,
    idj.id_proponent,
    idj.id_folder,
    idj.id_context_external,
    idj.statements_json_str,
    idj.payslips_json_str,
    idd.name,
    fd.document_ts_updated AS ts_updated_for_dedup,
    idj.type,
    idj.ts_credit_analysis_updated,
    idj.result,
    idj.reason,
    idj.analyst
  FROM
    income_document_joined AS idj
    INNER JOIN id_document_deduped AS idd ON idj.id_folder = idd.id_folder
    INNER JOIN filtered_documents AS fd ON idj.id = fd.document_id
),
data_deduped AS (
  SELECT
    id_proposal,
    id_proponent,
    id_folder,
    id_context_external,
    statements_json_str,
    payslips_json_str,
    name,
    type,
    ts_credit_analysis_updated,
    result,
    reason,
    analyst
  FROM
    data_joined
  QUALIFY
    ROW_NUMBER() OVER (
      PARTITION BY id_proposal, id_proponent
      ORDER BY ts_updated_for_dedup DESC
    ) = 1
),
documents_processed AS (
  SELECT
    id_proposal,
    id_proponent,
    id_folder,
    id_context_external,
    name,
    CASE
      WHEN SIZE(
        FROM_JSON(
          statements_json_str,
          'ARRAY<MAP<STRING, STRING>>'
        )
      ) = 0
      THEN NULL
      ELSE
        TRANSFORM(
          FROM_JSON(
            statements_json_str,
            'ARRAY<MAP<STRING, STRING>>'
          ),
          x -> x ['fileName']
        )
    END AS statements_array,
    CASE
      WHEN SIZE(
        FROM_JSON(
          payslips_json_str,
          'ARRAY<MAP<STRING, STRING>>'
        )
      ) = 0
      THEN NULL
      ELSE
        TRANSFORM(
          FROM_JSON(
            payslips_json_str,
            'ARRAY<MAP<STRING, STRING>>'
          ),
          x -> x ['fileName']
        )
    END AS payslips_array,
    type,
    ts_credit_analysis_updated,
    result,
    reason,
    analyst
  FROM
    data_deduped
),
final_documents_raw AS (
  SELECT
    id_proposal,
    id_proponent,
    id_folder,
    id_context_external,
    name,
    COALESCE(statements_array, payslips_array) AS documents,
    type,
    ts_credit_analysis_updated,
    result,
    reason,
    analyst
  FROM
    documents_processed
  WHERE
    COALESCE(statements_array, payslips_array) IS NOT NULL
)
SELECT
  id_proposal,
  name,
  type,
  ts_credit_analysis_updated,
  result,
  reason,
  analyst,
  ELEMENT_AT(documents, 1) AS document_1,
  ELEMENT_AT(documents, 2) AS document_2,
  ELEMENT_AT(documents, 3) AS document_3,
  ELEMENT_AT(documents, 4) AS document_4,
  ELEMENT_AT(documents, 5) AS document_5,
  ELEMENT_AT(documents, 6) AS document_6,
  ELEMENT_AT(documents, 7) AS document_7,
  ELEMENT_AT(documents, 8) AS document_8,
  ELEMENT_AT(documents, 9) AS document_9,
  ELEMENT_AT(documents, 10) AS document_10
FROM
  final_documents_raw
