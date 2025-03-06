WITH scr_data AS (
    SELECT
    id,
    cpf,
    `rev_end`,
    explode_outer(FROM_JSON(raw_data:analysis_output:scr.scr_data,
        'array<
        struct<
            source:string,
            indirect_risk:double,
            reference_date:string,
            operation_count:double,
            operation_items:array<struct<value:double,
            domain:string,
            modality:string,
            submodality:string,
            domain_group:string,
            modality_description:string,
            submodality_description:string,
            linked_to_foreign_currency:string>>,
            assumed_coobligation:string,
            receive_coobligation:string,
            start_relationship_date:string,
            subjudice_operations_count:string,
            subjudice_operations_value:string,
            financial_institution_count:string ,
            disagreement_operations_count:string,
            disagreement_operations_value:string
        >
        >')
    ) scr_data,
    aud.ts_created,
    rev.ts_created as ts_updated
  FROM datalake_arquivo_confidencial_clean.integration_report_aud AS aud
  LEFT JOIN datalake_arquivo_confidencial_clean.rev_info AS rev
    ON rev.rev = aud.rev
  WHERE integration_provider = 'QI_TECH_SCR'
    AND aud.ts_created >= DATE('2022-09-01')

),
mobs AS (
  SELECT
  distinct
    *,
    ROW_NUMBER() OVER (PARTITION BY cpf, ts_created ORDER BY scr_data.reference_date DESC) mob
  FROM scr_data
),
next_up AS (
  SELECT
    *,
    LEAD(ts_updated) OVER (PARTITION BY cpf, mob ORDER BY ts_created) ts_next_updated
  FROM mobs
),
operation_items_exploded AS (
  SELECT
    id,
    cpf,
    `rev_end`,
    mob,
    scr_data.reference_date,
    scr_data.financial_institution_count,
    scr_data.start_relationship_date,
    explode_outer(scr_data.operation_items) AS dat,
    ts_created,
    ts_updated,
    ts_next_updated
FROM next_up
)

SELECT
distinct
    id,
    cpf,
    `rev_end`,
    mob,
    reference_date,
    0.01*dat.value AS `value`,
    dat.domain,
    dat.modality,
    dat.submodality,
    dat.domain_group,
    dat.modality_description,
    dat.submodality_description,
    dat.linked_to_foreign_currency,
    financial_institution_count,
    start_relationship_date,
    ts_created,
    ts_updated,
    ts_next_updated
FROM operation_items_exploded
