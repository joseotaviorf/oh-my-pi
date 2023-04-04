WITH scr_data AS (
    SELECT
    id,
    cpf,
    `version`,
    EXPLODE(FROM_JSON(raw_data:analysis_output:scr.scr_data,
        'array<
        struct<
            source:string,
            indirect_risk:int,
            reference_date:string,
            operation_count:int,
            operation_items:array<struct<value:int,
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
    ts_created,
    ts_updated
  FROM datalake_arquivo_confidencial_clean.integration_report
  WHERE integration_provider = 'QI_TECH_SCR'
    AND ts_created >= DATE('2022-09-01')
),
mobs AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY cpf, `version` ORDER BY scr_data.reference_date DESC) mob
  FROM scr_data
),
operation_items_exploded AS (
  SELECT
    id,
    cpf,
    `version`,
    mob,
    scr_data.reference_date,
    EXPLODE(scr_data.operation_items) AS dat,
    ts_created,
    ts_updated
FROM mobs
)

SELECT
    id,
    cpf,
    `version`,
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
    ts_created,
    ts_updated
FROM operation_items_exploded
