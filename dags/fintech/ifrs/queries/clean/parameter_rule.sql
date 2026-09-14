SELECT
    sk_provision_rule AS id_provision_rule,
    rules_name AS rule_name,
    rule_type,
    rules,
    begin_date_application AS dt_begin_application,
    end_date_application AS dt_end_application
FROM
    datalake_ifrs_raw.parameter_rule
