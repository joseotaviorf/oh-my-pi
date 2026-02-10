WITH visit_per_identifier AS (
    SELECT
        sk_neotribe_exp,
        exp_name_neotribe,
        exp_name_experiment,
        exp_identifier_type,
        business_context,
        metric_cohort,
        sk_exp_identifier,
        dt_ref,
        -- number of identifiers
        COUNT(DISTINCT CASE WHEN exp_test_group = 'CONTROL' THEN number_identifiers END) AS count_identifiers_control,
        COUNT(DISTINCT CASE WHEN exp_test_group = 'TREATMENT' THEN number_identifiers END) AS count_identifiers_treatment,
        -- identifier vcf
        COUNT(DISTINCT CASE WHEN exp_test_group = 'CONTROL' THEN number_identifiers_with_vcf END) AS count_identifiers_with_vcf_control,
        COUNT(DISTINCT CASE WHEN exp_test_group = 'TREATMENT' THEN number_identifiers_with_vcf END) AS count_identifiers_with_vcf_treatment,
        -- identifier vc
        COUNT(DISTINCT CASE WHEN exp_test_group = 'CONTROL' THEN number_identifiers_with_vc END) AS count_identifiers_with_vc_control,
        COUNT(DISTINCT CASE WHEN exp_test_group = 'TREATMENT' THEN number_identifiers_with_vc END) AS count_identifiers_with_vc_treatment,
        -- identifier vcc
        COUNT(DISTINCT CASE WHEN exp_test_group = 'CONTROL' THEN number_identifiers_with_vcc END) AS count_identifiers_with_vcc_control,
        COUNT(DISTINCT CASE WHEN exp_test_group = 'TREATMENT' THEN number_identifiers_with_vcc END) AS count_identifiers_with_vcc_treatment,
        -- identifier vu
        COUNT(DISTINCT CASE WHEN exp_test_group = 'CONTROL' THEN number_identifiers_with_vu END) AS count_identifiers_with_vu_control,
        COUNT(DISTINCT CASE WHEN exp_test_group = 'TREATMENT' THEN number_identifiers_with_vu END) AS count_identifiers_with_vu_treatment,
        -- identifier os
        COUNT(DISTINCT CASE WHEN exp_test_group = 'CONTROL' THEN number_identifiers_with_os END) AS count_identifiers_with_os_control,
        COUNT(DISTINCT CASE WHEN exp_test_group = 'TREATMENT' THEN number_identifiers_with_os END) AS count_identifiers_with_os_treatment,
        -- identifier oa
        COUNT(DISTINCT CASE WHEN exp_test_group = 'CONTROL' THEN number_identifiers_with_oa END) AS count_identifiers_with_oa_control,
        COUNT(DISTINCT CASE WHEN exp_test_group = 'TREATMENT' THEN number_identifiers_with_oa END) AS count_identifiers_with_oa_treatment,
        -- identifier cs
        COUNT(DISTINCT CASE WHEN exp_test_group = 'CONTROL' THEN number_identifiers_with_cs END) AS count_identifiers_with_cs_control,
        COUNT(DISTINCT CASE WHEN exp_test_group = 'TREATMENT' THEN number_identifiers_with_cs END) AS count_identifiers_with_cs_treatment,
        -- number of vc
        SUM(CASE WHEN exp_test_group = 'CONTROL' THEN num_vc ELSE 0 END) AS sum_vc_control,
        SUM(CASE WHEN exp_test_group = 'TREATMENT' THEN num_vc ELSE 0 END) AS sum_vc_treatment,
        -- number of vcf
        SUM(CASE WHEN exp_test_group = 'CONTROL' THEN num_vcf ELSE 0 END) AS sum_vcf_control,
        SUM(CASE WHEN exp_test_group = 'TREATMENT' THEN num_vcf ELSE 0 END) AS sum_vcf_treatment,
        -- number of vcc
        SUM(CASE WHEN exp_test_group = 'CONTROL' THEN num_vcc ELSE 0 END) AS sum_vcc_control,
        SUM(CASE WHEN exp_test_group = 'TREATMENT' THEN num_vcc ELSE 0 END) AS sum_vcc_treatment,
        -- number of vu
        SUM(CASE WHEN exp_test_group = 'CONTROL' THEN num_vu ELSE 0 END) AS sum_vu_control,
        SUM(CASE WHEN exp_test_group = 'TREATMENT' THEN num_vu ELSE 0 END) AS sum_vu_treatment,
        -- number of os
        SUM(CASE WHEN exp_test_group = 'CONTROL' THEN num_os ELSE 0 END) AS sum_os_control,
        SUM(CASE WHEN exp_test_group = 'TREATMENT' THEN num_os ELSE 0 END) AS sum_os_treatment,
        -- number of oa
        SUM(CASE WHEN exp_test_group = 'CONTROL' THEN num_oa ELSE 0 END) AS sum_oa_control,
        SUM(CASE WHEN exp_test_group = 'TREATMENT' THEN num_oa ELSE 0 END) AS sum_oa_treatment,
        -- number of cs
        SUM(CASE WHEN exp_test_group = 'CONTROL' THEN num_cs ELSE 0 END) AS sum_cs_control,
        SUM(CASE WHEN exp_test_group = 'TREATMENT' THEN num_cs ELSE 0 END) AS sum_cs_treatment
    FROM
        metric_sale.exp_visit_cohort
    GROUP BY 1,2,3,4,5,6,7,8
),
visit_by_identifier AS (
    SELECT
        sk_neotribe_exp,
        exp_name_neotribe,
        exp_name_experiment,
        exp_identifier_type,
        business_context,
        metric_cohort,
        dt_ref,
        -- number of identifiers
        SUM(count_identifiers_control) AS sum_identifiers_control,
        SUM(count_identifiers_treatment) AS sum_identifiers_treatment,
        -- identifier vc
        SUM(count_identifiers_with_vc_control) AS sum_identifiers_with_vc_control,
        SUM(count_identifiers_with_vc_treatment) AS sum_identifiers_with_vc_treatment,
        (sum_identifiers_with_vc_control/sum_identifiers_control)*100 AS porc_identifier_with_vc_control,
        (sum_identifiers_with_vc_treatment/sum_identifiers_treatment)*100 AS porc_identifier_with_vc_treatment,
        1.96 * SQRT(sum_identifiers_with_vc_control / sum_identifiers_control * (1 - sum_identifiers_with_vc_control / sum_identifiers_control) / sum_identifiers_control) * 100 AS identifier_with_vc_control_error,
        1.96 * SQRT(sum_identifiers_with_vc_treatment / sum_identifiers_treatment * (1 - sum_identifiers_with_vc_treatment / sum_identifiers_treatment) / sum_identifiers_treatment) * 100 AS identifier_with_vc_treatment_error,
        -- identifier vcf
        SUM(count_identifiers_with_vcf_control) AS sum_identifiers_with_vcf_control,
        SUM(count_identifiers_with_vcf_treatment) AS sum_identifiers_with_vcf_treatment,
        (sum_identifiers_with_vcf_control/sum_identifiers_control)*100 AS porc_identifier_with_vcf_control,
        (sum_identifiers_with_vcf_treatment/sum_identifiers_treatment)*100 AS porc_identifier_with_vcf_treatment,
        1.96 * SQRT(sum_identifiers_with_vcf_control / sum_identifiers_control * (1 - sum_identifiers_with_vcf_control / sum_identifiers_control) / sum_identifiers_control) * 100 AS identifier_with_vcf_control_error,
        1.96 * SQRT(sum_identifiers_with_vcf_treatment / sum_identifiers_treatment * (1 - sum_identifiers_with_vcf_treatment / sum_identifiers_treatment) / sum_identifiers_treatment) * 100 AS identifier_with_vcf_treatment_error,
        -- identifier vcc
        SUM(count_identifiers_with_vcc_control) AS sum_identifiers_with_vcc_control,
        SUM(count_identifiers_with_vcc_treatment) AS sum_identifiers_with_vcc_treatment,
        (sum_identifiers_with_vcc_control/sum_identifiers_control)*100 AS porc_identifier_with_vcc_control,
        (sum_identifiers_with_vcc_treatment/sum_identifiers_treatment)*100 AS porc_identifier_with_vcc_treatment,
        1.96 * SQRT(sum_identifiers_with_vcc_control / sum_identifiers_control * (1 - sum_identifiers_with_vcc_control / sum_identifiers_control) / sum_identifiers_control) * 100 AS identifier_with_vcc_control_error,
        1.96 * SQRT(sum_identifiers_with_vcc_treatment / sum_identifiers_treatment * (1 - sum_identifiers_with_vcc_treatment / sum_identifiers_treatment) / sum_identifiers_treatment) * 100 AS identifier_with_vcc_treatment_error,
        -- identifier vu
        SUM(count_identifiers_with_vu_control) AS sum_identifiers_with_vu_control,
        SUM(count_identifiers_with_vu_treatment) AS sum_identifiers_with_vu_treatment,
        (sum_identifiers_with_vu_control/sum_identifiers_control)*100 AS porc_identifier_with_vu_control,
        (sum_identifiers_with_vu_treatment/sum_identifiers_treatment)*100 AS porc_identifier_with_vu_treatment,
        1.96 * SQRT(sum_identifiers_with_vu_control / sum_identifiers_control * (1 - sum_identifiers_with_vu_control / sum_identifiers_control) / sum_identifiers_control) * 100 AS identifier_with_vu_control_error,
        1.96 * SQRT(sum_identifiers_with_vu_treatment / sum_identifiers_treatment * (1 - sum_identifiers_with_vu_treatment / sum_identifiers_treatment) / sum_identifiers_treatment) * 100 AS identifier_with_vu_treatment_error,
        -- identifier os
        SUM(count_identifiers_with_os_control) AS sum_identifiers_with_os_control,
        SUM(count_identifiers_with_os_treatment) AS sum_identifiers_with_os_treatment,
        (sum_identifiers_with_os_control/sum_identifiers_control)*100 AS porc_identifier_with_os_control,
        (sum_identifiers_with_os_treatment/sum_identifiers_treatment)*100 AS porc_identifier_with_os_treatment,
        1.96 * SQRT(sum_identifiers_with_os_control / sum_identifiers_control * (1 - sum_identifiers_with_os_control / sum_identifiers_control) / sum_identifiers_control) * 100 AS identifier_with_os_control_error,
        1.96 * SQRT(sum_identifiers_with_os_treatment / sum_identifiers_treatment * (1 - sum_identifiers_with_os_treatment / sum_identifiers_treatment) / sum_identifiers_treatment) * 100 AS identifier_with_os_treatment_error,
        -- identifier oa
        SUM(count_identifiers_with_oa_control) AS sum_identifiers_with_oa_control,
        SUM(count_identifiers_with_oa_treatment) AS sum_identifiers_with_oa_treatment,
        (sum_identifiers_with_oa_control/sum_identifiers_control)*100 AS porc_identifier_with_oa_control,
        (sum_identifiers_with_oa_treatment/sum_identifiers_treatment)*100 AS porc_identifier_with_oa_treatment,
        1.96 * SQRT(sum_identifiers_with_oa_control / sum_identifiers_control * (1 - sum_identifiers_with_oa_control / sum_identifiers_control) / sum_identifiers_control) * 100 AS identifier_with_oa_control_error,
        1.96 * SQRT(sum_identifiers_with_oa_treatment / sum_identifiers_treatment * (1 - sum_identifiers_with_oa_treatment / sum_identifiers_treatment) / sum_identifiers_treatment) * 100 AS identifier_with_oa_treatment_error,
        -- identifier cs
        SUM(count_identifiers_with_cs_control) AS sum_identifiers_with_cs_control,
        SUM(count_identifiers_with_cs_treatment) AS sum_identifiers_with_cs_treatment,
        (sum_identifiers_with_cs_control/sum_identifiers_control)*100 AS porc_identifier_with_cs_control,
        (sum_identifiers_with_cs_treatment/sum_identifiers_treatment)*100 AS porc_identifier_with_cs_treatment,
        1.96 * SQRT(sum_identifiers_with_cs_control / sum_identifiers_control * (1 - sum_identifiers_with_cs_control / sum_identifiers_control) / sum_identifiers_control) * 100 AS identifier_with_cs_control_error,
        1.96 * SQRT(sum_identifiers_with_cs_treatment / sum_identifiers_treatment * (1 - sum_identifiers_with_cs_treatment / sum_identifiers_treatment) / sum_identifiers_treatment) * 100 AS identifier_with_cs_treatment_error,
        -- number of vc
        AVG(CASE WHEN count_identifiers_control != 0 THEN sum_vc_control ELSE NULL END) AS vc_per_identifier_control,
        AVG(CASE WHEN count_identifiers_treatment != 0 THEN sum_vc_treatment ELSE NULL END) AS vc_per_identifier_treatment,
        1.96 * STDDEV(IF(count_identifiers_control != 0, sum_vc_control, NULL)) / SQRT(SUM(count_identifiers_control)) AS vc_per_identifier_control_error,
        1.96 * STDDEV(IF(count_identifiers_treatment != 0, sum_vc_treatment, NULL)) / SQRT(SUM(count_identifiers_treatment)) AS vc_per_identifier_treatment_error,
        -- number of vcf
        AVG(CASE WHEN count_identifiers_control != 0 THEN sum_vcf_control ELSE NULL END) AS vcf_per_identifier_control,
        AVG(CASE WHEN count_identifiers_treatment != 0 THEN sum_vcf_treatment ELSE NULL END) AS vcf_per_identifier_treatment,
        1.96 * STDDEV(IF(count_identifiers_control != 0, sum_vcf_control, NULL)) / SQRT(SUM(count_identifiers_control)) AS vcf_per_identifier_control_error,
        1.96 * STDDEV(IF(count_identifiers_treatment != 0, sum_vcf_treatment, NULL)) / SQRT(SUM(count_identifiers_treatment)) AS vcf_per_identifier_treatment_error,
        -- number of vcc
        AVG(CASE WHEN count_identifiers_control != 0 THEN sum_vcc_control ELSE NULL END) AS vcc_per_identifier_control,
        AVG(CASE WHEN count_identifiers_treatment != 0 THEN sum_vcc_treatment ELSE NULL END) AS vcc_per_identifier_treatment,
        1.96 * STDDEV(IF(count_identifiers_control != 0, sum_vcc_control, NULL)) / SQRT(SUM(count_identifiers_control)) AS vcc_per_identifier_control_error,
        1.96 * STDDEV(IF(count_identifiers_treatment != 0, sum_vcc_treatment, NULL)) / SQRT(SUM(count_identifiers_treatment)) AS vcc_per_identifier_treatment_error,
        -- number of vu
        AVG(CASE WHEN count_identifiers_control != 0 THEN sum_vu_control ELSE NULL END) AS vu_per_identifier_control,
        AVG(CASE WHEN count_identifiers_treatment != 0 THEN sum_vu_treatment ELSE NULL END) AS vu_per_identifier_treatment,
        1.96 * STDDEV(IF(count_identifiers_control != 0, sum_vu_control, NULL)) / SQRT(SUM(count_identifiers_control)) AS vu_per_identifier_control_error,
        1.96 * STDDEV(IF(count_identifiers_treatment != 0, sum_vu_treatment, NULL)) / SQRT(SUM(count_identifiers_treatment)) AS vu_per_identifier_treatment_error,
        -- number of os
        AVG(CASE WHEN count_identifiers_control != 0 THEN sum_os_control ELSE NULL END) AS os_per_identifier_control,
        AVG(CASE WHEN count_identifiers_treatment != 0 THEN sum_os_treatment ELSE NULL END) AS os_per_identifier_treatment,
        1.96 * STDDEV(IF(count_identifiers_control != 0, sum_os_control, NULL)) / SQRT(SUM(count_identifiers_control)) AS os_per_identifier_control_error,
        1.96 * STDDEV(IF(count_identifiers_treatment != 0, sum_os_treatment, NULL)) / SQRT(SUM(count_identifiers_treatment)) AS os_per_identifier_treatment_error,
        -- number of oa
        AVG(CASE WHEN count_identifiers_control != 0 THEN sum_oa_control ELSE NULL END) AS oa_per_identifier_control,
        AVG(CASE WHEN count_identifiers_treatment != 0 THEN sum_oa_treatment ELSE NULL END) AS oa_per_identifier_treatment,
        1.96 * STDDEV(IF(count_identifiers_control != 0, sum_oa_control, NULL)) / SQRT(SUM(count_identifiers_control)) AS oa_per_identifier_control_error,
        1.96 * STDDEV(IF(count_identifiers_treatment != 0, sum_oa_treatment, NULL)) / SQRT(SUM(count_identifiers_treatment)) AS oa_per_identifier_treatment_error,
        -- number of cs
        AVG(CASE WHEN count_identifiers_control != 0 THEN sum_cs_control ELSE NULL END) AS cs_per_identifier_control,
        AVG(CASE WHEN count_identifiers_treatment != 0 THEN sum_cs_treatment ELSE NULL END) AS cs_per_identifier_treatment,
        1.96 * STDDEV(IF(count_identifiers_control != 0, sum_cs_control, NULL)) / SQRT(SUM(count_identifiers_control)) AS cs_per_identifier_control_error,
        1.96 * STDDEV(IF(count_identifiers_treatment != 0, sum_cs_treatment, NULL)) / SQRT(SUM(count_identifiers_treatment)) AS cs_per_identifier_treatment_error
    FROM
        visit_per_identifier
    GROUP BY 1,2,3,4,5,6,7
)
SELECT
    MD5(vbi.sk_neotribe_exp || vbi.metric_cohort || vbi.dt_ref || m.metric_name) AS sk_exp_visit_metric,
    vbi.exp_name_neotribe,
    vbi.exp_name_experiment,
    vbi.exp_identifier_type,
    vbi.business_context,
    vbi.metric_cohort,
    m.metric_name,
    m.control_metric_value,
    m.control_metric_error,
    m.treatment_metric_value,
    m.treatment_metric_error,
    vbi.dt_ref
FROM
    visit_by_identifier AS vbi
LATERAL VIEW
    STACK(
        22, -- Number of metrics

        'number_identifiers', CAST(vbi.sum_identifiers_control AS DOUBLE), CAST(NULL AS DOUBLE), CAST(vbi.sum_identifiers_treatment AS DOUBLE), CAST(NULL AS DOUBLE),

        'number_identifiers_with_vc', CAST(vbi.sum_identifiers_with_vc_control AS DOUBLE), CAST(NULL AS DOUBLE), CAST(vbi.sum_identifiers_with_vc_treatment AS DOUBLE), CAST(NULL AS DOUBLE),

        'number_identifiers_with_vcf', CAST(vbi.sum_identifiers_with_vcf_control AS DOUBLE), CAST(NULL AS DOUBLE), CAST(vbi.sum_identifiers_with_vcf_treatment AS DOUBLE), CAST(NULL AS DOUBLE),

        'number_identifiers_with_vcc', CAST(vbi.sum_identifiers_with_vcc_control AS DOUBLE), CAST(NULL AS DOUBLE), CAST(vbi.sum_identifiers_with_vcc_treatment AS DOUBLE), CAST(NULL AS DOUBLE),

        'number_identifiers_with_vu', CAST(vbi.sum_identifiers_with_vu_control AS DOUBLE), CAST(NULL AS DOUBLE), CAST(vbi.sum_identifiers_with_vu_treatment AS DOUBLE), CAST(NULL AS DOUBLE),

        'number_identifiers_with_os', CAST(vbi.sum_identifiers_with_os_control AS DOUBLE), CAST(NULL AS DOUBLE), CAST(vbi.sum_identifiers_with_os_treatment AS DOUBLE), CAST(NULL AS DOUBLE),

        'number_identifiers_with_oa', CAST(vbi.sum_identifiers_with_oa_control AS DOUBLE), CAST(NULL AS DOUBLE), CAST(vbi.sum_identifiers_with_oa_treatment AS DOUBLE), CAST(NULL AS DOUBLE),

        'number_identifiers_with_cs', CAST(vbi.sum_identifiers_with_cs_control AS DOUBLE), CAST(NULL AS DOUBLE), CAST(vbi.sum_identifiers_with_cs_treatment AS DOUBLE), CAST(NULL AS DOUBLE),

        'identifier_with_vc', vbi.porc_identifier_with_vc_control, vbi.identifier_with_vc_control_error, vbi.porc_identifier_with_vc_treatment, vbi.identifier_with_vc_treatment_error,

        'identifier_with_vcf', vbi.porc_identifier_with_vcf_control, vbi.identifier_with_vcf_control_error, vbi.porc_identifier_with_vcf_treatment, vbi.identifier_with_vcf_treatment_error,

        'identifier_with_vcc', vbi.porc_identifier_with_vcc_control, vbi.identifier_with_vcc_control_error, vbi.porc_identifier_with_vcc_treatment, vbi.identifier_with_vcc_treatment_error,

        'identifier_with_vu', vbi.porc_identifier_with_vu_control, vbi.identifier_with_vu_control_error, vbi.porc_identifier_with_vu_treatment, vbi.identifier_with_vu_treatment_error,

        'identifier_with_os', vbi.porc_identifier_with_os_control, vbi.identifier_with_os_control_error, vbi.porc_identifier_with_os_treatment, vbi.identifier_with_os_treatment_error,

        'identifier_with_oa', vbi.porc_identifier_with_oa_control, vbi.identifier_with_oa_control_error, vbi.porc_identifier_with_oa_treatment, vbi.identifier_with_oa_treatment_error,

        'identifier_with_cs', vbi.porc_identifier_with_cs_control, vbi.identifier_with_cs_control_error, vbi.porc_identifier_with_cs_treatment, vbi.identifier_with_cs_treatment_error,

        'vc_per_identifier', vbi.vc_per_identifier_control, vbi.vc_per_identifier_control_error, vbi.vc_per_identifier_treatment, vbi.vc_per_identifier_treatment_error,

        'vcf_per_identifier', vbi.vcf_per_identifier_control, vbi.vcf_per_identifier_control_error, vbi.vcf_per_identifier_treatment, vbi.vcf_per_identifier_treatment_error,

        'vcc_per_identifier', vbi.vcc_per_identifier_control, vbi.vcc_per_identifier_control_error, vbi.vcc_per_identifier_treatment, vbi.vcc_per_identifier_treatment_error,

        'vu_per_identifier', vbi.vu_per_identifier_control, vbi.vu_per_identifier_control_error, vbi.vu_per_identifier_treatment, vbi.vu_per_identifier_treatment_error,

        'os_per_identifier', vbi.os_per_identifier_control, vbi.os_per_identifier_control_error, vbi.os_per_identifier_treatment, vbi.os_per_identifier_treatment_error,

        'oa_per_identifier', vbi.oa_per_identifier_control, vbi.oa_per_identifier_control_error, vbi.oa_per_identifier_treatment, vbi.oa_per_identifier_treatment_error,

        'cs_per_identifier', vbi.cs_per_identifier_control, vbi.cs_per_identifier_control_error, vbi.cs_per_identifier_treatment, vbi.cs_per_identifier_treatment_error
    ) m AS metric_name, control_metric_value, control_metric_error, treatment_metric_value, treatment_metric_error
