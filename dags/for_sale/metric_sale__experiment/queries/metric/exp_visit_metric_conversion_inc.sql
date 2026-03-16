WITH visit_metrics AS (
    SELECT
        sk_neotribe_exp,
        exp_name_neotribe,
        exp_name_experiment,
        exp_identifier_type,
        business_context,
        metric_cohort,
        dt_ref,
        -- vb
        SUM(CASE WHEN exp_test_group = 'CONTROL' THEN num_vb ELSE 0 END) AS sum_vb_control,
        SUM(CASE WHEN exp_test_group = 'TREATMENT' THEN num_vb ELSE 0 END) AS sum_vb_treatment,
        -- vcf
        SUM(CASE WHEN exp_test_group = 'CONTROL' THEN num_vcf ELSE 0 END) AS sum_vcf_control,
        SUM(CASE WHEN exp_test_group = 'TREATMENT' THEN num_vcf ELSE 0 END) AS sum_vcf_treatment,
        (sum_vcf_control/sum_vb_control)*100 AS vb2vcf_control,
        (sum_vcf_treatment/sum_vb_treatment)*100 AS vb2vcf_treatment,
        1.96 * SQRT(sum_vcf_control / sum_vb_control * (1 - sum_vcf_control / sum_vb_control) / sum_vb_control) * 100 AS vb2vcf_control_error,
        1.96 * SQRT(sum_vcf_treatment / sum_vb_treatment * (1 - sum_vcf_treatment / sum_vb_treatment) / sum_vb_treatment) * 100 AS vb2vcf_treatment_error,
        -- vc
        SUM(CASE WHEN exp_test_group = 'CONTROL' THEN num_vc ELSE 0 END) AS sum_vc_control,
        SUM(CASE WHEN exp_test_group = 'TREATMENT' THEN num_vc ELSE 0 END) AS sum_vc_treatment,
        (sum_vc_control/sum_vb_control)*100 AS vb2vc_control,
        (sum_vc_control/sum_vcf_control)*100 AS vcf2vc_control,
        (sum_vc_treatment/sum_vb_treatment)*100 AS vb2vc_treatment,
        (sum_vc_treatment/sum_vcf_treatment)*100 AS vcf2vc_treatment,
        1.96 * SQRT(sum_vc_control / sum_vb_control * (1 - sum_vc_control / sum_vb_control) / sum_vb_control) * 100 AS vb2vc_control_error,
        1.96 * SQRT(sum_vc_control / sum_vcf_control * (1 - sum_vc_control / sum_vcf_control) / sum_vcf_control) * 100 AS vcf2vc_control_error,
        1.96 * SQRT(sum_vc_treatment / sum_vb_treatment * (1 - sum_vc_treatment / sum_vb_treatment) / sum_vb_treatment) * 100 AS vb2vc_treatment_error,
        1.96 * SQRT(sum_vc_treatment / sum_vcf_treatment * (1 - sum_vc_treatment / sum_vcf_treatment) / sum_vcf_treatment) * 100 AS vcf2vc_treatment_error,
        -- vcc
        SUM(CASE WHEN exp_test_group = 'CONTROL' THEN num_vcc ELSE 0 END) AS sum_vcc_control,
        SUM(CASE WHEN exp_test_group = 'TREATMENT' THEN num_vcc ELSE 0 END) AS sum_vcc_treatment,
        (sum_vcc_control/sum_vb_control)*100 AS vb2vcc_control,
        (sum_vcc_treatment/sum_vb_treatment)*100 AS vb2vcc_treatment,
        1.96 * SQRT(sum_vcc_control / sum_vb_control * (1 - sum_vcc_control / sum_vb_control) / sum_vb_control) * 100 AS vb2vcc_control_error,
        1.96 * SQRT(sum_vcc_treatment / sum_vb_treatment * (1 - sum_vcc_treatment / sum_vb_treatment) / sum_vb_treatment) * 100 AS vb2vcc_treatment_error,
        -- vu
        SUM(CASE WHEN exp_test_group = 'CONTROL' THEN num_vu ELSE 0 END) AS sum_vu_control,
        SUM(CASE WHEN exp_test_group = 'TREATMENT' THEN num_vu ELSE 0 END) AS sum_vu_treatment,
        (sum_vu_control/sum_vb_control)*100 AS vb2vu_control,
        (sum_vu_treatment/sum_vb_treatment)*100 AS vb2vu_treatment,
        1.96 * SQRT(sum_vu_control / sum_vb_control * (1 - sum_vu_control / sum_vb_control) / sum_vb_control) * 100 AS vb2vu_control_error,
        1.96 * SQRT(sum_vu_treatment / sum_vb_treatment * (1 - sum_vu_treatment / sum_vb_treatment) / sum_vb_treatment) * 100 AS vb2vu_treatment_error,
        -- os
        SUM(CASE WHEN exp_test_group = 'CONTROL' THEN num_os ELSE 0 END) AS sum_os_control,
        SUM(CASE WHEN exp_test_group = 'TREATMENT' THEN num_os ELSE 0 END) AS sum_os_treatment,
        (sum_os_control/sum_vb_control)*100 AS vb2os_control,
        (sum_os_treatment/sum_vb_treatment)*100 AS vb2os_treatment,
        1.96 * SQRT(sum_os_control / sum_vb_control * (1 - sum_os_control / sum_vb_control) / sum_vb_control) * 100 AS vb2os_control_error,
        1.96 * SQRT(sum_os_treatment / sum_vb_treatment * (1 - sum_os_treatment / sum_vb_treatment) / sum_vb_treatment) * 100 AS vb2os_treatment_error,
        -- oa
        SUM(CASE WHEN exp_test_group = 'CONTROL' THEN num_oa ELSE 0 END) AS sum_oa_control,
        SUM(CASE WHEN exp_test_group = 'TREATMENT' THEN num_oa ELSE 0 END) AS sum_oa_treatment,
        (sum_oa_control/sum_vb_control)*100 AS vb2oa_control,
        (sum_oa_treatment/sum_vb_treatment)*100 AS vb2oa_treatment,
        1.96 * SQRT(sum_oa_control / sum_vb_control * (1 - sum_oa_control / sum_vb_control) / sum_vb_control) * 100 AS vb2oa_control_error,
        1.96 * SQRT(sum_oa_treatment / sum_vb_treatment * (1 - sum_oa_treatment / sum_vb_treatment) / sum_vb_treatment) * 100 AS vb2oa_treatment_error,
        -- cs
        SUM(CASE WHEN exp_test_group = 'CONTROL' THEN num_cs ELSE 0 END) AS sum_cs_control,
        SUM(CASE WHEN exp_test_group = 'TREATMENT' THEN num_cs ELSE 0 END) AS sum_cs_treatment,
        (sum_cs_control/sum_vb_control)*100 AS vb2cs_control,
        (sum_cs_treatment/sum_vb_treatment)*100 AS vb2cs_treatment,
        1.96 * SQRT(sum_cs_control / sum_vb_control * (1 - sum_cs_control / sum_vb_control) / sum_vb_control) * 100 AS vb2cs_control_error,
        1.96 * SQRT(sum_cs_treatment / sum_vb_treatment * (1 - sum_cs_treatment / sum_vb_treatment) / sum_vb_treatment) * 100 AS vb2cs_treatment_error
    FROM
        metric_sale.exp_visit_cohort_inc
    WHERE
        dt_ref BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
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
        15, -- Number of metrics

        'number_vc', CAST(vm.sum_vc_control AS DOUBLE), CAST(NULL AS DOUBLE), CAST(vm.sum_vc_treatment AS DOUBLE), CAST(NULL AS DOUBLE),

        'number_vcf', CAST(vm.sum_vcf_control AS DOUBLE), CAST(NULL AS DOUBLE), CAST(vm.sum_vcf_treatment AS DOUBLE), CAST(NULL AS DOUBLE),

        'number_vcc', CAST(vm.sum_vcc_control AS DOUBLE), CAST(NULL AS DOUBLE), CAST(vm.sum_vcc_treatment AS DOUBLE), CAST(NULL AS DOUBLE),

        'number_vu', CAST(vm.sum_vu_control AS DOUBLE), CAST(NULL AS DOUBLE), CAST(vm.sum_vu_treatment AS DOUBLE), CAST(NULL AS DOUBLE),

        'number_os', CAST(vm.sum_os_control AS DOUBLE), CAST(NULL AS DOUBLE), CAST(vm.sum_os_treatment AS DOUBLE), CAST(NULL AS DOUBLE),

        'number_oa', CAST(vm.sum_oa_control AS DOUBLE), CAST(NULL AS DOUBLE), CAST(vm.sum_oa_treatment AS DOUBLE), CAST(NULL AS DOUBLE),

        'number_cs', CAST(vm.sum_cs_control AS DOUBLE), CAST(NULL AS DOUBLE), CAST(vm.sum_cs_treatment AS DOUBLE), CAST(NULL AS DOUBLE),

        'vb2vc', vm.vb2vc_control, vm.vb2vc_control_error, vm.vb2vc_treatment, vm.vb2vc_treatment_error,

        'vcf2vc', vm.vcf2vc_control, vm.vcf2vc_control_error, vm.vcf2vc_treatment, vm.vcf2vc_treatment_error,

        'vb2vcf', vm.vb2vcf_control, vm.vb2vcf_control_error, vm.vb2vcf_treatment, vm.vb2vcf_treatment_error,

        'vb2vcc', vm.vb2vcc_control, vm.vb2vcc_control_error, vm.vb2vcc_treatment, vm.vb2vcc_treatment_error,

        'vb2vu', vm.vb2vu_control, vm.vb2vu_control_error, vm.vb2vu_treatment, vm.vb2vu_treatment_error,

        'vb2os', vm.vb2os_control, vm.vb2os_control_error, vm.vb2os_treatment, vm.vb2os_treatment_error,

        'vb2oa', vm.vb2oa_control, vm.vb2oa_control_error, vm.vb2oa_treatment, vm.vb2oa_treatment_error,

        'vb2cs_or_ccv', vm.vb2cs_control, vm.vb2cs_control_error, vm.vb2cs_treatment, vm.vb2cs_treatment_error
    ) m AS metric_name, control_metric_value, control_metric_error, treatment_metric_value, treatment_metric_error
