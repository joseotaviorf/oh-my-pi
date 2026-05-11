WITH credit_policy_report_parse_json AS (
    SELECT
        id,
        id_external,
        external_source,
        version,
        FROM_JSON(raw_data, 'STRUCT<
            is_retenant: BOOLEAN,
            variant: STRING,
            risk_category: STRING,
            risk_category_canon: STRING,
            calibrated_score: DOUBLE,
            city: STRING,
            state: STRING,
            passport_city: STRING,
            passport_state: STRING,
            package_value: DOUBLE,
            total_income: DOUBLE
        >') AS raw_data_parsed,
        FROM_JSON(result, 'STRUCT<
            analysis_category: INT,
            rejection_reason: STRING,
            policy_dti: STRING,
            score: INT,
            calibrated_score: DOUBLE,
            errors: ARRAY<STRING>,
            is_mock: BOOLEAN,
            execution_context: STRUCT<
                city_group: STRING,
                experiment_groups: ARRAY<STRING>,
                policy_matrix: STRING,
                house_random_percentage: INT
            >
        >') AS result_parsed,
        ts_created,
        ts_updated
    FROM
        datalake_sorting_hat_clean.policy_report
    WHERE
        type = 'CREDIT_POLICY'
),
credit_policy_report AS (
    SELECT
        id AS id_policy_report,
        id_external,
        external_source,
        CASE
            WHEN external_source = 'PROPOSAL' THEN TRY_CAST(id_external AS INT)
        END AS id_proposal,
        CASE
            WHEN external_source = 'CREDIT_EVALUATION' THEN TRY_CAST(id_external AS INT)
        END AS id_credit_evaluation,
        CAST(version AS INTEGER) AS version,
        raw_data_parsed.is_retenant,
        raw_data_parsed.variant,
        raw_data_parsed.risk_category,
        raw_data_parsed.risk_category_canon,
        raw_data_parsed.city,
        raw_data_parsed.state,
        raw_data_parsed.passport_city,
        raw_data_parsed.passport_state,
        raw_data_parsed.calibrated_score,
        raw_data_parsed.total_income,
        raw_data_parsed.package_value,
        result_parsed.analysis_category,
        result_parsed.rejection_reason,
        result_parsed.policy_dti,
        result_parsed.score,
        result_parsed.calibrated_score AS result_calibrated_score,
        ARRAY_SIZE(result_parsed.errors) > 0 AS is_error_present,
        result_parsed.execution_context.city_group AS city_group,
        result_parsed.execution_context.policy_matrix AS policy_matrix,
        result_parsed.execution_context.house_random_percentage AS house_random_percentage,
        result_parsed.execution_context.experiment_groups AS experiment_groups_array,
        result_parsed.is_mock,
        ts_created,
        ts_updated
    FROM
        credit_policy_report_parse_json
),
retenant_policy_report_parse_json AS (
    SELECT
        external_source,
        id_external,
        ts_updated,
        FROM_JSON(result, 'STRUCT<
            type: STRING,
            elected_contract_guarantee_type: STRING
        >') AS result_parsed
    FROM
        datalake_sorting_hat_clean.policy_report
    WHERE
        type = 'RETENANT'
),
retenant_policy_report AS (
    SELECT
        external_source,
        id_external,
        ts_updated AS retenant_ts_updated,
        result_parsed.type AS retenant_result_type,
        result_parsed.elected_contract_guarantee_type AS retenant_guarantee_type
    FROM
        retenant_policy_report_parse_json
),
link_credit_evaluation_proposal AS (
    SELECT
        credit_policy_report.id_policy_report,
        MAX_BY(credit_evaluation.id, credit_evaluation.ts_created) AS id_credit_evaluation
    FROM
        credit_policy_report
        INNER JOIN datalake_docx_clean.credit_evaluation
            ON credit_evaluation.id_proposal = credit_policy_report.id_proposal
            AND credit_evaluation.ts_created <= credit_policy_report.ts_updated
            AND credit_evaluation.ts_updated >= credit_policy_report.ts_updated
    WHERE
        credit_policy_report.external_source = 'PROPOSAL'
    GROUP BY
        credit_policy_report.id_policy_report
)
SELECT
    credit_policy_report.id_policy_report,
    COALESCE(
        credit_policy_report.id_credit_evaluation,
        link_credit_evaluation_proposal.id_credit_evaluation
    ) AS id_credit_evaluation,
    credit_policy_report.id_proposal,
    credit_policy_report.id_external,
    credit_policy_report.external_source,
    credit_policy_report.version,
    credit_policy_report.variant,
    credit_policy_report.is_retenant,
    CASE
        WHEN (retenant_policy_report.retenant_result_type IS NULL
              OR retenant_policy_report.retenant_result_type = 'NEW_USER') THEN 'NEW_USER'
        WHEN retenant_policy_report.retenant_guarantee_type = 'SeguroFairfax' THEN 'FREE_RETENANT'
        WHEN retenant_policy_report.retenant_guarantee_type IS NOT NULL THEN 'PAID_RETENANT'
    END AS retenant_type,
    CASE
        WHEN retenant_policy_report.retenant_ts_updated IS NULL THEN FALSE
        WHEN retenant_policy_report.retenant_ts_updated < credit_policy_report.ts_updated THEN TRUE
        ELSE FALSE
    END AS is_retenant_type_trusted,
    credit_policy_report.risk_category,
    credit_policy_report.risk_category_canon,
    credit_policy_report.city,
    credit_policy_report.state,
    credit_policy_report.passport_city,
    credit_policy_report.passport_state,
    credit_policy_report.rejection_reason,
    credit_policy_report.policy_dti,
    credit_policy_report.city_group,
    credit_policy_report.policy_matrix,
    credit_policy_report.is_error_present,
    credit_policy_report.analysis_category,
    CASE
        WHEN credit_policy_report.rejection_reason IS NOT NULL
            AND credit_policy_report.rejection_reason != 'BAD_SCORE_ALL_PROPONENTS' THEN NULL
        WHEN credit_policy_report.analysis_category = 0 THEN 'FREE'
        WHEN credit_policy_report.analysis_category = 1 THEN 'INSURANCE_50_PERC'
        WHEN credit_policy_report.analysis_category = 3 THEN 'INSURANCE_75_PERC'
        WHEN credit_policy_report.analysis_category = 7 THEN 'INSURANCE_50_PERC_OR_DEPOSIT_3x'
        WHEN credit_policy_report.analysis_category = 8 THEN 'INSURANCE_50_PERC_OR_DEPOSIT_4x'
        WHEN credit_policy_report.analysis_category = 9 THEN 'INSURANCE_50_PERC_OR_DEPOSIT_5x'
        WHEN credit_policy_report.analysis_category = 10 THEN 'INSURANCE_50_PERC_OR_DEPOSIT_6x'
        WHEN credit_policy_report.analysis_category = 11 THEN 'INSURANCE_50_PERC_OR_DEPOSIT_7x'
        WHEN credit_policy_report.analysis_category = 12 THEN 'INSURANCE_50_PERC_OR_DEPOSIT_8x'
        WHEN credit_policy_report.analysis_category = 13 THEN 'INSURANCE_75_PERC_OR_DEPOSIT_3x'
        WHEN credit_policy_report.analysis_category = 14 THEN 'INSURANCE_75_PERC_OR_DEPOSIT_4x'
        WHEN credit_policy_report.analysis_category = 15 THEN 'INSURANCE_75_PERC_OR_DEPOSIT_5x'
        WHEN credit_policy_report.analysis_category = 16 THEN 'INSURANCE_75_PERC_OR_DEPOSIT_6x'
        WHEN credit_policy_report.analysis_category = 17 THEN 'INSURANCE_75_PERC_OR_DEPOSIT_7x'
        WHEN credit_policy_report.analysis_category = 18 THEN 'INSURANCE_75_PERC_OR_DEPOSIT_8x'
        WHEN credit_policy_report.analysis_category = 19 THEN 'INSURANCE_75_PERC_OR_DEPOSIT_9x'
        WHEN credit_policy_report.analysis_category = 42 THEN 'DEPOSIT_3x'
        WHEN credit_policy_report.analysis_category = 20 THEN 'DEPOSIT_6x'
        WHEN credit_policy_report.analysis_category = 21 THEN 'DEPOSIT_7x'
        WHEN credit_policy_report.analysis_category = 22 THEN 'DEPOSIT_8x'
        WHEN credit_policy_report.analysis_category = 23 THEN 'DEPOSIT_9x'
        WHEN credit_policy_report.analysis_category = 24 THEN 'DEPOSIT_10x'
        WHEN credit_policy_report.analysis_category = 25 THEN 'PRO_GUARANTOR_50_PERC'
        WHEN credit_policy_report.analysis_category = 26 THEN 'PRO_GUARANTOR_75_PERC'
        WHEN credit_policy_report.analysis_category = 55 THEN 'PRO_GUARANTOR_100_PERC'
        WHEN credit_policy_report.analysis_category = 56 THEN 'PRO_GUARANTOR_125_PERC'
        WHEN credit_policy_report.analysis_category = 27 THEN 'PRO_GUARANTOR_50_PERC_OR_DEPOSIT_3x'
        WHEN credit_policy_report.analysis_category = 28 THEN 'PRO_GUARANTOR_50_PERC_OR_DEPOSIT_4x'
        WHEN credit_policy_report.analysis_category = 29 THEN 'PRO_GUARANTOR_50_PERC_OR_DEPOSIT_5x'
        WHEN credit_policy_report.analysis_category = 30 THEN 'PRO_GUARANTOR_50_PERC_OR_DEPOSIT_6x'
        WHEN credit_policy_report.analysis_category = 31 THEN 'PRO_GUARANTOR_50_PERC_OR_DEPOSIT_7x'
        WHEN credit_policy_report.analysis_category = 32 THEN 'PRO_GUARANTOR_50_PERC_OR_DEPOSIT_8x'
        WHEN credit_policy_report.analysis_category = 33 THEN 'PRO_GUARANTOR_75_PERC_OR_DEPOSIT_3x'
        WHEN credit_policy_report.analysis_category = 34 THEN 'PRO_GUARANTOR_75_PERC_OR_DEPOSIT_4x'
        WHEN credit_policy_report.analysis_category = 35 THEN 'PRO_GUARANTOR_75_PERC_OR_DEPOSIT_5x'
        WHEN credit_policy_report.analysis_category = 36 THEN 'PRO_GUARANTOR_75_PERC_OR_DEPOSIT_6x'
        WHEN credit_policy_report.analysis_category = 37 THEN 'PRO_GUARANTOR_75_PERC_OR_DEPOSIT_7x'
        WHEN credit_policy_report.analysis_category = 38 THEN 'PRO_GUARANTOR_75_PERC_OR_DEPOSIT_8x'
        WHEN credit_policy_report.analysis_category = 39 THEN 'PRO_GUARANTOR_75_PERC_OR_DEPOSIT_9x'
        WHEN credit_policy_report.analysis_category = 43 THEN 'PRO_GUARANTOR_100_PERC_OR_DEPOSIT_3x'
        WHEN credit_policy_report.analysis_category = 44 THEN 'PRO_GUARANTOR_100_PERC_OR_DEPOSIT_4x'
        WHEN credit_policy_report.analysis_category = 45 THEN 'PRO_GUARANTOR_100_PERC_OR_DEPOSIT_5x'
        WHEN credit_policy_report.analysis_category = 46 THEN 'PRO_GUARANTOR_100_PERC_OR_DEPOSIT_6x'
        WHEN credit_policy_report.analysis_category = 47 THEN 'PRO_GUARANTOR_100_PERC_OR_DEPOSIT_7x'
        WHEN credit_policy_report.analysis_category = 48 THEN 'PRO_GUARANTOR_100_PERC_OR_DEPOSIT_8x'
        WHEN credit_policy_report.analysis_category = 57 THEN 'PRO_GUARANTOR_100_PERC_OR_DEPOSIT_9x'
        WHEN credit_policy_report.analysis_category = 49 THEN 'PRO_GUARANTOR_125_PERC_OR_DEPOSIT_3x'
        WHEN credit_policy_report.analysis_category = 50 THEN 'PRO_GUARANTOR_125_PERC_OR_DEPOSIT_4x'
        WHEN credit_policy_report.analysis_category = 51 THEN 'PRO_GUARANTOR_125_PERC_OR_DEPOSIT_5x'
        WHEN credit_policy_report.analysis_category = 52 THEN 'PRO_GUARANTOR_125_PERC_OR_DEPOSIT_6x'
        WHEN credit_policy_report.analysis_category = 53 THEN 'PRO_GUARANTOR_125_PERC_OR_DEPOSIT_7x'
        WHEN credit_policy_report.analysis_category = 54 THEN 'PRO_GUARANTOR_125_PERC_OR_DEPOSIT_8x'
        WHEN credit_policy_report.analysis_category = 40 THEN 'STANDALONE_LOW_PERC'
        WHEN credit_policy_report.analysis_category = 41 THEN 'STANDALONE_HIGH_PERC'
        WHEN credit_policy_report.analysis_category IS NULL THEN 'CLEAR_NO'
        WHEN credit_policy_report.analysis_category = 58 THEN 'THIRD_PARTY_GUARANTEE'
    END AS analysis_category_name,
    CASE
        WHEN credit_policy_report.experiment_groups_array IS NULL
            OR ARRAY_SIZE(credit_policy_report.experiment_groups_array) = 0 THEN NULL
        ELSE MAP_FROM_ENTRIES(
            TRANSFORM(
                credit_policy_report.experiment_groups_array,
                x -> STRUCT(
                    REGEXP_REPLACE(x, '_[^_]+$', '') AS key,
                    REGEXP_EXTRACT(x, '_([^_]+)$', 1) AS value
                )
            )
        )
    END AS experiment_groups,
    credit_policy_report.calibrated_score,
    credit_policy_report.score,
    credit_policy_report.total_income,
    credit_policy_report.package_value,
    credit_policy_report.house_random_percentage,
    CASE
        WHEN credit_policy_report.total_income IS NULL THEN NULL
        WHEN credit_policy_report.total_income <= 7500 THEN 'LOW_INCOME'
        ELSE 'HIGH_INCOME'
    END AS income_group,
    CASE
        WHEN credit_policy_report.risk_category_canon BETWEEN 'A1' AND 'A3' THEN '[A1,A3]'
        WHEN credit_policy_report.risk_category_canon BETWEEN 'A4' AND 'B1' THEN '[A4,B1]'
        WHEN credit_policy_report.risk_category_canon BETWEEN 'B2' AND 'D2' THEN '[B2,D2]'
        WHEN credit_policy_report.risk_category_canon BETWEEN 'D3' AND 'F1' THEN '[D3,F1]'
        WHEN credit_policy_report.risk_category_canon BETWEEN 'F2' AND 'I2' THEN '[F2,I2]'
        WHEN credit_policy_report.risk_category_canon >= 'I3' THEN '[I3,J1]'
    END AS risk_category_range,
    credit_policy_report.ts_created,
    credit_policy_report.ts_updated
FROM
    credit_policy_report
    LEFT JOIN link_credit_evaluation_proposal
        ON credit_policy_report.id_policy_report = link_credit_evaluation_proposal.id_policy_report
    LEFT JOIN retenant_policy_report
        ON retenant_policy_report.external_source = credit_policy_report.external_source
        AND retenant_policy_report.id_external = credit_policy_report.id_external
