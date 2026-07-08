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

SELECT experiment_name, config
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
                                                    'experiment_metrics', array("search_ctr")
                                                )
                                ),
           'running', False
        )
    ),
    -- Geo-embeddings on CG experiment
    (
        "ab_beakman_search_services_location_embedding_on_cg_experiment",
        named_struct(
            'begin_date', DATE('2025-08-06'),
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
                                                    'experiment_metrics', array()
                                                )
                                ),
           'running', False
        )
    ),
     -- Demand balancer v1 map and SSR rent experiment
    (
        "ab_beakman_search_services_demand_concentration_v1_map_and_ssr_rent_experiment_v2",
        named_struct(
            'begin_date', DATE('2025-08-14'),
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
                                                    'experiment_metrics', array()
                                                )
                                ),
           'running', False
        )
    ),

    -- Demand balancer v1 Recs rent experiment
    (
        "ab_beakman_search_services_demand_concentration_v1_recs_rent_experiment",
        named_struct(
            'begin_date', DATE('2025-09-15'),
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
                                                    'experiment_metrics', array()
                                                )
                                ),
           'running', False
        )
    ),

    -- New feed experiment
    (
        "ab_beakman_native_home_feed_recommendations_experiment",
        named_struct(
            'begin_date', DATE('2025-11-18'),
            'end_date', DATE('2026-01-11'),
            'variants', to_json(
                named_struct(
                    'baseline', 'baseline',
                    'treatment', 'treatment'
                )
            ),
            'filters', NULL,
            'metrics', to_json(
                                    named_struct(
                                                    'default_metrics', true,
                                                    'experiment_metrics', array()
                                                )
                                ),
           'running', False
        )
    ),

    -- New Pclick Rent Exp
    (
        "ab_beakman_search_services_p_click_experiment_v7",
        named_struct(
            'begin_date', DATE('2025-12-06'),
            'end_date', DATE('2026-01-21'),
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
                                                    'experiment_metrics', array()
                                                )
                                ),
           'running', False
        )
    ),

    -- New Pclick Sale Exp
    (
        "ab_beakman_search_services_p_click_experiment_sale_v7",
        named_struct(
            'begin_date', DATE('2026-01-21'),
            'end_date', DATE('2026-03-17'),
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
                                                    'experiment_metrics', array()
                                                )
                                ),
           'running', False
        )
    ),

    -- HUE V3 Rent exp
    (
        "ab_beakman_search_services_hue_v3_experiment",
        named_struct(
            'begin_date', DATE('2025-12-10'),
            'end_date', DATE('2026-01-18'),
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
                                                    'experiment_metrics', array()
                                                )
                                ),
           'running', False
        )
    ),

        -- HUE V3 Sale exp
    (
        "ab_beakman_search_services_hue_v3_experiment_v3_sale",
        named_struct(
            'begin_date', DATE('2026-02-27'),
            'end_date', DATE('2026-04-07'),
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
                                                    'experiment_metrics', array()
                                                )
                                ),
           'running', False
        )
    ),

    -- Recs using only user profile essential filters for sale
    (
        "ab_beakman_search_services_feed_filter_search_profile_sale_experiment",
        named_struct(
            'begin_date', DATE('2026-05-07'),
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
                                                    'experiment_metrics', array()
                                                )
                                ),
           'running', True
        )
    ),

    -- Recs using search profile feed filter for sale
    (
        "ab_beakman_search_services_feed_filter_search_profile_sale_experiment_v2",
        named_struct(
            'begin_date', DATE('2026-05-23'),
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
                                                    'experiment_metrics', array()
                                                )
                                ),
           'running', True
        )
    ),

    (
        "ab_beakman_search_services_anonymous_user_embedding_fallback",
        named_struct(
            'begin_date', DATE('2026-03-25'),
            'end_date', DATE('2026-04-08'),
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
                                                    'experiment_metrics', array()
                                                )
                                ),
           'running', True
        )
    ),

    -- Feed sequence experiment
    (
        "ab_beakman_search_services_feed_sequence_experiment_v2",
        named_struct(
            'begin_date', DATE('2026-05-28'),
            'end_date', DATE('2026-06-29'),
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
                                                    'experiment_metrics', array()
                                                )
                                ),
           'running', True
        )
    ),

    -- Real Time Search Profile Exp
    (
        "ab_beakman_search_services_search_profile_v2",
        named_struct(
            'begin_date', DATE('2026-05-04'),
            'end_date', DATE('2026-06-29'),
            'variants', to_json(
                named_struct(
                    'VARIANT_A', 'baseline',
                    'VARIANT_B', 'treatment'
                )
            ),
            'filters', NULL,
            'metrics', to_json(
                                    named_struct(
                                                    'default_metrics', true,
                                                    'experiment_metrics', array()
                                                )
                                ),
           'running', True
        )
    ),

    -- SENNA Rent
    (
        "ab_beakman_search_services_senna_embedding_rent_experiment_v2",
        named_struct(
            'begin_date', DATE('2026-07-08'),
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
                                                    'experiment_metrics', array()
                                                )
                                ),
           'running', True
        )
    ),

    -- SENNA Sale
    (
        "ab_beakman_search_services_senna_embedding_sale_experiment_v2",
        named_struct(
            'begin_date', DATE('2026-07-08'),
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
                                                    'experiment_metrics', array()
                                                )
                                ),
           'running', True
        )
    ),

    -- Dynamic Carousels Rent
    (
        "ab_beakman_search_services_dynamic_carousels_rent_v2",
        named_struct(
            'begin_date', DATE('2026-07-08'),
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
                                                    'experiment_metrics', array()
                                                )
                                ),
           'running', True
        )
    ),

    -- Dynamic Carousels Sale
    (
        "ab_beakman_search_services_dynamic_carousels_sale_v2",
        named_struct(
            'begin_date', DATE('2026-07-08'),
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
                                                    'experiment_metrics', array()
                                                )
                                ),
           'running', True
        )
    )

AS experiment_config(experiment_name, config)
