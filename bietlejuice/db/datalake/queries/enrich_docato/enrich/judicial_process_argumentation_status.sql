WITH 
    argumentation AS (
        SELECT 
            judicial_process,
            employer_mandatory_training,
            seller_broker_ranking,
            appraisals_by_the_contractor,
            imposing_sales_targets,
            freedom_to_negotiate_commissions,
            company_management_over_the_complainant,
            penalties_for_fouls,
            wearing_uniform_badge,
            schedule_freedom,
            obligation_to_attend_the_sales_booth,
            commission_paid_in_case_of_buyer_default,
            creci_after_the_service_provision,
            charge_for_sales_reports,
            service_provision_contract_in_the_union,
            selection_process_for_seller_broker,
            employment_termination_rules_application_in_the_contract,
            minimum_monthly_guarantee_value,
            employer_mandatory_training_second_instance,
            seller_broker_ranking_second_instance,
            appraisals_by_the_contractor_second_instance,
            imposing_sales_targets_second_instance,
            freedom_to_negotiate_commissions_second_instance,
            company_management_over_the_complainant_second_instance,
            penalties_for_fouls_second_instance,
            wearing_uniform_badge_second_instance,
            schedule_freedom_second_instance,
            obligation_to_attend_the_sales_booth_second_instance,
            commission_paid_in_case_of_buyer_default_second_instance,
            creci_after_the_service_provision_second_instance,
            charge_for_sales_reports_second_instance,
            service_provision_contract_in_the_union_second_instance,
            selection_process_for_seller_broker_second_instance,
            employment_termination_rules_application_in_the_contract_second_instance,
            minimum_monthly_guarantee_value_second_instance,
            COALESCE(employer_mandatory_training_second_instance, employer_mandatory_training) AS employer_mandatory_training_last,
            COALESCE(seller_broker_ranking_second_instance, seller_broker_ranking) AS seller_broker_ranking_last,
            COALESCE(appraisals_by_the_contractor_second_instance, appraisals_by_the_contractor) AS appraisals_by_the_contractor_last,
            COALESCE(imposing_sales_targets_second_instance, imposing_sales_targets) AS imposing_sales_targets_last,
            COALESCE(freedom_to_negotiate_commissions_second_instance, freedom_to_negotiate_commissions) AS freedom_to_negotiate_commissions_last,
            COALESCE(company_management_over_the_complainant_second_instance, company_management_over_the_complainant) AS company_management_over_the_complainant_last,
            COALESCE(penalties_for_fouls_second_instance, penalties_for_fouls) AS penalties_for_fouls_last,
            COALESCE(wearing_uniform_badge_second_instance, wearing_uniform_badge) AS wearing_uniform_badge_last,
            COALESCE(schedule_freedom_second_instance, schedule_freedom) AS schedule_freedom_last,
            COALESCE(obligation_to_attend_the_sales_booth_second_instance, obligation_to_attend_the_sales_booth) AS obligation_to_attend_the_sales_booth_last,
            COALESCE(commission_paid_in_case_of_buyer_default_second_instance, commission_paid_in_case_of_buyer_default) AS commission_paid_in_case_of_buyer_default_last,
            COALESCE(creci_after_the_service_provision_second_instance, creci_after_the_service_provision) AS creci_after_the_service_provision_last,
            COALESCE(charge_for_sales_reports_second_instance, charge_for_sales_reports) AS charge_for_sales_reports_last,
            COALESCE(service_provision_contract_in_the_union_second_instance, service_provision_contract_in_the_union) AS service_provision_contract_in_the_union_last,
            COALESCE(selection_process_for_seller_broker_second_instance, selection_process_for_seller_broker) AS selection_process_for_seller_broker_last,
            COALESCE(employment_termination_rules_application_in_the_contract_second_instance, employment_termination_rules_application_in_the_contract) AS employment_termination_rules_application_in_the_contract_last,
            COALESCE(minimum_monthly_guarantee_value_second_instance, minimum_monthly_guarantee_value) as minimum_monthly_guarantee_value_last
        FROM 
            datalake_gsheets_clean.legal_base_docato
    ),

    argumentation_unpivot AS (
        SELECT 
            judicial_process, 
            stack(51, 'appraisals_by_the_contractor_last', appraisals_by_the_contractor_last, 
            'appraisals_by_the_contractor_second_instance', appraisals_by_the_contractor_second_instance, 
            'appraisals_by_the_contractor', appraisals_by_the_contractor, 
            'charge_for_sales_reports_last', charge_for_sales_reports_last, 
            'charge_for_sales_reports_second_instance', charge_for_sales_reports_second_instance, 
            'charge_for_sales_reports', charge_for_sales_reports, 
            'commission_paid_in_case_of_buyer_default_last', commission_paid_in_case_of_buyer_default_last, 
            'commission_paid_in_case_of_buyer_default_second_instance', commission_paid_in_case_of_buyer_default_second_instance, 
            'commission_paid_in_case_of_buyer_default', commission_paid_in_case_of_buyer_default, 
            'company_management_over_the_complainant_last', company_management_over_the_complainant_last, 
            'company_management_over_the_complainant_second_instance', company_management_over_the_complainant_second_instance, 
            'company_management_over_the_complainant', company_management_over_the_complainant, 
            'creci_after_the_service_provision_last', creci_after_the_service_provision_last, 
            'creci_after_the_service_provision_second_instance', creci_after_the_service_provision_second_instance, 
            'creci_after_the_service_provision', creci_after_the_service_provision, 
            'employer_mandatory_training_last', employer_mandatory_training_last, 
            'employer_mandatory_training_second_instance', employer_mandatory_training_second_instance, 
            'employer_mandatory_training', employer_mandatory_training, 
            'employment_termination_rules_application_in_the_contract_last', employment_termination_rules_application_in_the_contract_last, 
            'employment_termination_rules_application_in_the_contract_second_instance', employment_termination_rules_application_in_the_contract_second_instance, 
            'employment_termination_rules_application_in_the_contract', employment_termination_rules_application_in_the_contract, 
            'freedom_to_negotiate_commissions_last', freedom_to_negotiate_commissions_last, 
            'freedom_to_negotiate_commissions_second_instance', freedom_to_negotiate_commissions_second_instance, 
            'freedom_to_negotiate_commissions', freedom_to_negotiate_commissions, 
            'imposing_sales_targets_last', imposing_sales_targets_last, 
            'imposing_sales_targets_second_instance', imposing_sales_targets_second_instance, 
            'imposing_sales_targets', imposing_sales_targets, 
            'minimum_monthly_guarantee_value_last', minimum_monthly_guarantee_value_last, 
            'minimum_monthly_guarantee_value_second_instance', minimum_monthly_guarantee_value_second_instance, 
            'minimum_monthly_guarantee_value', minimum_monthly_guarantee_value, 
            'obligation_to_attend_the_sales_booth_last', obligation_to_attend_the_sales_booth_last, 
            'obligation_to_attend_the_sales_booth_second_instance', obligation_to_attend_the_sales_booth_second_instance, 
            'obligation_to_attend_the_sales_booth', obligation_to_attend_the_sales_booth, 
            'penalties_for_fouls_last', penalties_for_fouls_last, 
            'penalties_for_fouls_second_instance', penalties_for_fouls_second_instance, 
            'penalties_for_fouls', penalties_for_fouls, 
            'schedule_freedom_last', schedule_freedom_last, 
            'schedule_freedom_second_instance', schedule_freedom_second_instance, 
            'schedule_freedom', schedule_freedom, 
            'selection_process_for_seller_broker_last', selection_process_for_seller_broker_last, 
            'selection_process_for_seller_broker_second_instance', selection_process_for_seller_broker_second_instance, 
            'selection_process_for_seller_broker', selection_process_for_seller_broker, 
            'seller_broker_ranking_last', seller_broker_ranking_last, 
            'seller_broker_ranking_second_instance', seller_broker_ranking_second_instance, 
            'seller_broker_ranking', seller_broker_ranking, 
            'service_provision_contract_in_the_union_last', service_provision_contract_in_the_union_last, 
            'service_provision_contract_in_the_union_second_instance', service_provision_contract_in_the_union_second_instance, 
            'service_provision_contract_in_the_union', service_provision_contract_in_the_union, 
            'wearing_uniform_badge_last', wearing_uniform_badge_last, 
            'wearing_uniform_badge_second_instance', wearing_uniform_badge_second_instance, 
            'wearing_uniform_badge', wearing_uniform_badge) AS (arguments, result)
        FROM 
            argumentation
    ),

    argumentation_unpivot_clean AS (
        SELECT 
            judicial_process,
            CASE
                WHEN SUBSTRING(arguments, -5) = '_last' THEN LEFT(arguments, LENGTH(arguments) - 5)
                WHEN SUBSTRING(arguments, -16) = '_second_instance' THEN LEFT(arguments, LENGTH(arguments) - 16)
                ELSE arguments
            END AS argument,
            CASE
                WHEN SUBSTRING(arguments, -5) = '_last' THEN 'last'
                WHEN SUBSTRING(arguments, -16) = '_second_instance' THEN 'second instance'
                ELSE 'first'
            END AS instance,
            CASE
                WHEN result IN ('Não Havia', 'Não', 'Não havia', 'não havia', 'Nâo') THEN  'no'
                WHEN result IN ('Sim', 'Havia', 'sim') THEN 'yes'
                ELSE NULL
            END AS result
        FROM 
            argumentation_unpivot
    )

SELECT 
    judicial_process,
    argument,
    instance,
    result
FROM 
    argumentation_unpivot_clean