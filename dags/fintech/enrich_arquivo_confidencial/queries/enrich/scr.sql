WITH scr_data AS (
    SELECT
        aud.id,
        aud.cpf,
        aud.`rev_end`,
        CASE
            WHEN GET_JSON_OBJECT(aud.attributes, '$.analysis_output.scr.scr_data') IS NULL THEN 0
            ELSE 1
        END AS has_scr_attributes,
        explode_outer(
            FROM_JSON(
                GET_JSON_OBJECT(aud.raw_data, '$.analysis_output.scr.scr_data'),
                'array<struct<\n                source:string,\n                indirect_risk:double,\n                reference_date:string,\n                operation_count:double,\n                operation_items:array<struct<\n                  value:double,\n                  domain:string,\n                  modality:string,\n                  submodality:string,\n                  domain_group:string,\n                  modality_description:string,\n                  submodality_description:string,\n                  linked_to_foreign_currency:string\n                >>,\n                assumed_coobligation:string,\n                receive_coobligation:string,\n                start_relationship_date:string,\n                subjudice_operations_count:string,\n                subjudice_operations_value:string,\n                financial_institution_count:string,\n                disagreement_operations_count:string,\n                disagreement_operations_value:string\n            >>'
            )
        ) AS scr_data,
        aud.ts_created,
        rev.ts_created AS ts_updated
    FROM
        datalake_arquivo_confidencial_clean.integration_report_aud AS aud
    LEFT JOIN
        datalake_arquivo_confidencial_clean.rev_info AS rev
            ON rev.rev = aud.rev
    WHERE
        aud.integration_provider = 'QI_TECH_SCR'
        AND aud.ts_created >= DATE('2022-09-01')
),
mobs AS (
    SELECT
        id,
        cpf,
        `rev_end`,
        has_scr_attributes,
        scr_data,
        ts_created,
        ts_updated,
        ROW_NUMBER() OVER (
            PARTITION BY cpf, ts_created
            ORDER BY scr_data.reference_date DESC
        ) AS mob
    FROM
        scr_data
),
next_up AS (
    SELECT
        id,
        cpf,
        `rev_end`,
        has_scr_attributes,
        scr_data,
        ts_created,
        ts_updated,
        mob,
        LEAD(ts_updated) OVER (
            PARTITION BY cpf, mob
            ORDER BY ts_created
        ) AS ts_next_updated
    FROM
        mobs
),
operation_items_exploded AS (
    SELECT
        id,
        cpf,
        `rev_end`,
        mob,
        has_scr_attributes,
        scr_data.reference_date,
        scr_data.financial_institution_count,
        scr_data.start_relationship_date,
        explode_outer(scr_data.operation_items) AS dat,
        ts_created,
        ts_updated,
        ts_next_updated
    FROM
        next_up
)
-- DISTINCT retained: explode can emit duplicate operation_items; dropping it
-- changes volumetry. Window CTEs above use explicit columns to shrink shuffle.
SELECT DISTINCT
    id,
    cpf,
    `rev_end`,
    mob,
    dat.domain,
    dat.modality,
    dat.submodality,
    dat.domain_group,
    dat.modality_description,
    dat.submodality_description,
    dat.linked_to_foreign_currency,
    0.01 * dat.value AS `value`,
    financial_institution_count,
    has_scr_attributes,
    reference_date,
    start_relationship_date,
    ts_created,
    ts_updated,
    ts_next_updated
FROM
    operation_items_exploded
