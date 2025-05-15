/*
This table has the configuration of the experiments.

To add a new experiment:
Add
````
    ,(
        "experiment name here",
        named_struct(
            'begin_date', DATE('the begin date here'),
            'end_date', DATE('the end date here'), -- Or NULL, at the end edit to add te end date
            'variants', to_json(
                named_struct(
                    -- add the name(s) of each variant and map to the standard name
                    -- Standard variant names: baseline, treatment_1, treatment_2, ....
                    '0', 'baseline',
                    'baseline', 'baseline'
                    'another_name_for_baseline', 'baseline',
                    'offline', 'baseline',
                    '1', 'treatment_1',
                    'online', 'treatment_1',
                    '2', 'treatment_2',
                    '3', 'treatment_3'
                    ....
                )
            ),
            'filters',
            -- Add and sql expression to filter the experiment participants here
            "business_context = 'rent' "\
            "AND id_user IS NOT NULL"
        )
    )
```

Edit an experiment:
Change the config you want.
Ex: change
```'end_date',  NULL,```
to
```'end_date', DATE('2024-06-01'),```

LIST OF DEFAULT METRICS:
- search_to_global_offer_14_days
- search_to_global_visit_14_days
- search_to_global_contract_14_days
- search_to_global_offer_14_days_distinct_users
- search_to_global_visit_14_days_distinct_users
- house_published_to_global_offer_14_days
- house_published_to_global_visit_14_days
- house_published_to_global_contract_14_days

Nondefault metrics:
- search_ctr

For full list of metrics, see the file: models/search/search-monitoring/search_monitoring/batch/metrics/metrics_dict.py

*/

SELECT
    *
FROM VALUES
    -- dummy experiment to have the field types correct.
    -- Otherwise if all end_date are null it raises error due to unknown data type
    (
        "dummy_experiment",
        named_struct(
            'begin_date', DATE('2001-01-01'),
            'end_date', DATE('2001-01-02'),
            'variants', to_json(
                named_struct(
                    '0', 'baseline',
                    '1', 'treatment'
                )
            ),
            'filters', "business_context = 'sale'",
            'metrics', to_json(
                                    named_struct(
                                                    'default_metrics', true,
                                                    'experiment_metrics', ["search_ctr"]
                                                )
                                )
        )
    ),
    -- demand balancer v2 policy v2
    (
        "ab_beakman_search_services_demand_concentration_v2_policy_3_rent_experiment",
        named_struct(
            'begin_date', DATE('2025-04-08'),
            'end_date', NULL,
            'variants', to_json(
                named_struct(
                    '0', 'baseline',
                    '1', 'treatment'
                )
            ),
            'filters', "business_context = 'rent'",
            'metrics', to_json(
                                    named_struct(
                                                    'default_metrics', true,
                                                )
                                )
        )
    ),
    -- HUE vs listing-claw (LTR)
    (
        "ab_beakman_search_services_hue_candidate_generation_experiment_v2",
        named_struct(
            'begin_date', DATE('2025-03-19'),
            'end_date', NULL,
            'variants', to_json(
                named_struct(
                    '0', 'baseline',
                    '1', 'treatment'
                )
            ),
            'filters', NULL,
            'metrics', to_json(
                                    named_struct(
                                                    'default_metrics', true,
                                                )
                                )
        )
    ),
    -- Important experience from a different team
    (
        "ab_beakman_wpp_alert_v2",
        named_struct(
            'begin_date', DATE('2025-04-06'),
            'end_date', NULL,
            'variants', to_json(
                named_struct(
                    '0', 'baseline',
                    '1', 'treatment'
                )
            ),
            'filters', NULL,
            'metrics', to_json(
                                    named_struct(
                                                    'default_metrics', true,
                                                )
                                )
        )
    ),
    -- HUE VS HSE for Rent
    (
        "AB_TEST_RECS_HUE_ITEM_RENT_V2",
        named_struct(
            'begin_date', DATE('2025-04-09'),
            'end_date', NULL,
            'variants', to_json(
                named_struct(
                    '0', 'baseline',
                    '1', 'treatment'
                )
            ),
            'filters', "business_context = 'rent'",
            'metrics', to_json(
                                    named_struct(
                                                    'default_metrics', true,
                                                )
                                )
        )
    ),
    -- HUE VS HSE for Sale
    (
        "AB_TEST_RECS_HUE_ITEM_SALE_V2",
        named_struct(
            'begin_date', DATE('2025-04-09'),
            'end_date', NULL,
            'variants', to_json(
                named_struct(
                    '0', 'baseline',
                    '1', 'treatment'
                )
            ),
            'filters', "business_context = 'sale'",
            'metrics', to_json(
                                    named_struct(
                                                    'default_metrics', true,
                                                )
                                )
        )
    ),
    -- Listing recs pricing experiment
    (
        "ab_beakman_listing_recs_vs_pricing_experiment",
        named_struct(
            'begin_date', DATE('2025-02-27'),
            'end_date', NULL,
            'variants', to_json(
                named_struct(
                    '0', 'baseline',
                    '1', 'treatment'
                )
            ),
            'filters', NULL,
            'metrics', to_json(
                                    named_struct(
                                                    'default_metrics', true,
                                                )
                                )
        )
    )
    -- Add new experiment here



AS experiment_config(experiment_name, config)
