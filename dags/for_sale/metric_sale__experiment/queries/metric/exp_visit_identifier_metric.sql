WITH visit_metrics AS (
    SELECT
        sk_neotribe_exp,
        exp_name_neotribe,
        exp_name_experiment,
        exp_identifier_type,
        business_context,
        metric_cohort,
        dt_ref,
        -- number of identifiers
        COUNT(DISTINCT CASE WHEN exp_test_group = 'CONTROL' THEN number_identifiers END) AS count_identifiers_control,
        COUNT(DISTINCT CASE WHEN exp_test_group = 'TREATMENT' THEN number_identifiers END) AS count_identifiers_treatment,
        -- identifier vc
        COUNT(DISTINCT CASE WHEN exp_test_group = 'CONTROL' THEN number_identifiers_with_vc END) AS count_identifiers_with_vc_control,
        COUNT(DISTINCT CASE WHEN exp_test_group = 'TREATMENT' THEN number_identifiers_with_vc END) AS count_identifiers_with_vc_treatment,
        (count_identifiers_with_vc_control/count_identifiers_control)*100 AS porc_identifier_with_vc_control,
        (count_identifiers_with_vc_treatment/count_identifiers_treatment)*100 AS porc_identifier_with_vc_treatment,
        1.96 * SQRT(count_identifiers_with_vc_control / count_identifiers_control * (1 - count_identifiers_with_vc_control / count_identifiers_control) / count_identifiers_control) * 100 AS identifier_with_vc_control_error,
        1.96 * SQRT(count_identifiers_with_vc_treatment / count_identifiers_treatment * (1 - count_identifiers_with_vc_treatment / count_identifiers_treatment) / count_identifiers_treatment) * 100 AS identifier_with_vc_treatment_error,
        -- identifier vcc
        COUNT(DISTINCT CASE WHEN exp_test_group = 'CONTROL' THEN number_identifiers_with_vcc END) AS count_identifiers_with_vcc_control,
        COUNT(DISTINCT CASE WHEN exp_test_group = 'TREATMENT' THEN number_identifiers_with_vcc END) AS count_identifiers_with_vcc_treatment,
        (count_identifiers_with_vcc_control/count_identifiers_control)*100 AS porc_identifier_with_vcc_control,
        (count_identifiers_with_vcc_treatment/count_identifiers_treatment)*100 AS porc_identifier_with_vcc_treatment,
        1.96 * SQRT(count_identifiers_with_vcc_control / count_identifiers_control * (1 - count_identifiers_with_vcc_control / count_identifiers_control) / count_identifiers_control) * 100 AS identifier_with_vcc_control_error,
        1.96 * SQRT(count_identifiers_with_vcc_treatment / count_identifiers_treatment * (1 - count_identifiers_with_vcc_treatment / count_identifiers_treatment) / count_identifiers_treatment) * 100 AS identifier_with_vcc_treatment_error,
        -- identifier vu
        COUNT(DISTINCT CASE WHEN exp_test_group = 'CONTROL' THEN number_identifiers_with_vu END) AS count_identifiers_with_vu_control,
        COUNT(DISTINCT CASE WHEN exp_test_group = 'TREATMENT' THEN number_identifiers_with_vu END) AS count_identifiers_with_vu_treatment,
        (count_identifiers_with_vu_control/count_identifiers_control)*100 AS porc_identifier_with_vu_control,
        (count_identifiers_with_vu_treatment/count_identifiers_treatment)*100 AS porc_identifier_with_vu_treatment,
        1.96 * SQRT(count_identifiers_with_vu_control / count_identifiers_control * (1 - count_identifiers_with_vu_control / count_identifiers_control) / count_identifiers_control) * 100 AS identifier_with_vu_control_error,
        1.96 * SQRT(count_identifiers_with_vu_treatment / count_identifiers_treatment * (1 - count_identifiers_with_vu_treatment / count_identifiers_treatment) / count_identifiers_treatment) * 100 AS identifier_with_vu_treatment_error,
        -- identifier os
        COUNT(DISTINCT CASE WHEN exp_test_group = 'CONTROL' THEN number_identifiers_with_os END) AS count_identifiers_with_os_control,
        COUNT(DISTINCT CASE WHEN exp_test_group = 'TREATMENT' THEN number_identifiers_with_os END) AS count_identifiers_with_os_treatment,
        (count_identifiers_with_os_control/count_identifiers_control)*100 AS porc_identifier_with_os_control,
        (count_identifiers_with_os_treatment/count_identifiers_treatment)*100 AS porc_identifier_with_os_treatment,
        1.96 * SQRT(count_identifiers_with_os_control / count_identifiers_control * (1 - count_identifiers_with_os_control / count_identifiers_control) / count_identifiers_control) * 100 AS identifier_with_os_control_error,
        1.96 * SQRT(count_identifiers_with_os_treatment / count_identifiers_treatment * (1 - count_identifiers_with_os_treatment / count_identifiers_treatment) / count_identifiers_treatment) * 100 AS identifier_with_os_treatment_error,
        -- identifier oa
        COUNT(DISTINCT CASE WHEN exp_test_group = 'CONTROL' THEN number_identifiers_with_oa END) AS count_identifiers_with_oa_control,
        COUNT(DISTINCT CASE WHEN exp_test_group = 'TREATMENT' THEN number_identifiers_with_oa END) AS count_identifiers_with_oa_treatment,
        (count_identifiers_with_oa_control/count_identifiers_control)*100 AS porc_identifier_with_oa_control,
        (count_identifiers_with_oa_treatment/count_identifiers_treatment)*100 AS porc_identifier_with_oa_treatment,
        1.96 * SQRT(count_identifiers_with_oa_control / count_identifiers_control * (1 - count_identifiers_with_oa_control / count_identifiers_control) / count_identifiers_control) * 100 AS identifier_with_oa_control_error,
        1.96 * SQRT(count_identifiers_with_oa_treatment / count_identifiers_treatment * (1 - count_identifiers_with_oa_treatment / count_identifiers_treatment) / count_identifiers_treatment) * 100 AS identifier_with_oa_treatment_error,
        -- identifier cs
        COUNT(DISTINCT CASE WHEN exp_test_group = 'CONTROL' THEN number_identifiers_with_cs END) AS count_identifiers_with_cs_control,
        COUNT(DISTINCT CASE WHEN exp_test_group = 'TREATMENT' THEN number_identifiers_with_cs END) AS count_identifiers_with_cs_treatment,
        (count_identifiers_with_cs_control/count_identifiers_control)*100 AS porc_identifier_with_cs_control,
        (count_identifiers_with_cs_treatment/count_identifiers_treatment)*100 AS porc_identifier_with_cs_treatment,
        1.96 * SQRT(count_identifiers_with_cs_control / count_identifiers_control * (1 - count_identifiers_with_cs_control / count_identifiers_control) / count_identifiers_control) * 100 AS identifier_with_cs_control_error,
        1.96 * SQRT(count_identifiers_with_cs_treatment / count_identifiers_treatment * (1 - count_identifiers_with_cs_treatment / count_identifiers_treatment) / count_identifiers_treatment) * 100 AS identifier_with_cs_treatment_error
    FROM
        metric_sale.exp_visit_cohort
    GROUP BY 1,2,3,4,5,6,7
)
SELECT
    MD5(vm.sk_neotribe_exp || vm.metric_cohort || vm.dt_ref || m.metric_name) AS sk_exp_visit_metric,
    vm.exp_name_neotribe,
    vm.exp_name_experiment,
    vm.exp_identifier_type,
    vm.business_context,
    vm.metric_cohort,
    m.metric_name,
    m.control_metric_value,
    m.control_metric_error,
    m.treatment_metric_value,
    m.treatment_metric_error,
    vm.dt_ref
FROM
    visit_metrics AS vm
LATERAL VIEW
    STACK(
        13, -- Number of metrics

        'number_identifiers', CAST(vm.count_identifiers_control AS DOUBLE), CAST(NULL AS DOUBLE), CAST(vm.count_identifiers_treatment AS DOUBLE), CAST(NULL AS DOUBLE),

        'number_identifiers_with_vc', CAST(vm.count_identifiers_with_vc_control AS DOUBLE), CAST(NULL AS DOUBLE), CAST(vm.count_identifiers_with_vc_treatment AS DOUBLE), CAST(NULL AS DOUBLE),

        'number_identifiers_with_vcc', CAST(vm.count_identifiers_with_vcc_control AS DOUBLE), CAST(NULL AS DOUBLE), CAST(vm.count_identifiers_with_vcc_treatment AS DOUBLE), CAST(NULL AS DOUBLE),

        'number_identifiers_with_vu', CAST(vm.count_identifiers_with_vu_control AS DOUBLE), CAST(NULL AS DOUBLE), CAST(vm.count_identifiers_with_vu_treatment AS DOUBLE), CAST(NULL AS DOUBLE),

        'number_identifiers_with_os', CAST(vm.count_identifiers_with_os_control AS DOUBLE), CAST(NULL AS DOUBLE), CAST(vm.count_identifiers_with_os_treatment AS DOUBLE), CAST(NULL AS DOUBLE),

        'number_identifiers_with_oa', CAST(vm.count_identifiers_with_oa_control AS DOUBLE), CAST(NULL AS DOUBLE), CAST(vm.count_identifiers_with_oa_treatment AS DOUBLE), CAST(NULL AS DOUBLE),

        'number_identifiers_with_cs', CAST(vm.count_identifiers_with_cs_control AS DOUBLE), CAST(NULL AS DOUBLE), CAST(vm.count_identifiers_with_cs_treatment AS DOUBLE), CAST(NULL AS DOUBLE),

        'identifier_with_vc', vm.porc_identifier_with_vc_control, vm.identifier_with_vc_control_error, vm.porc_identifier_with_vc_treatment, vm.identifier_with_vc_treatment_error,

        'identifier_with_vcc', vm.porc_identifier_with_vcc_control, vm.identifier_with_vcc_control_error, vm.porc_identifier_with_vcc_treatment, vm.identifier_with_vcc_treatment_error,

        'identifier_with_vu', vm.porc_identifier_with_vu_control, vm.identifier_with_vu_control_error, vm.porc_identifier_with_vu_treatment, vm.identifier_with_vu_treatment_error,

        'identifier_with_os', vm.porc_identifier_with_os_control, vm.identifier_with_os_control_error, vm.porc_identifier_with_os_treatment, vm.identifier_with_os_treatment_error,

        'identifier_with_oa', vm.porc_identifier_with_oa_control, vm.identifier_with_oa_control_error, vm.porc_identifier_with_oa_treatment, vm.identifier_with_oa_treatment_error,

        'identifier_with_cs', vm.porc_identifier_with_cs_control, vm.identifier_with_cs_control_error, vm.porc_identifier_with_cs_treatment, vm.identifier_with_cs_treatment_error
    ) m AS metric_name, control_metric_value, control_metric_error, treatment_metric_value, treatment_metric_error
