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
            'filters', "business_context = 'sale'"
        )
    ),
    -- demand balancer v2 policy v2
    (
        "ab_beakman_search_services_demand_concentration_v2_policy_2_rent_experiment",
        named_struct(
            'begin_date', DATE('2025-02-17'),
            'end_date', NULL,
            'variants', to_json(
                named_struct(
                    '-1', 'baseline_contaminated',
                    '0', 'baseline',
                    '1', 'treatment_1',
                    '2', 'treatment_2'
                )
            ),
            'filters', "business_context = 'rent'"
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
            'filters', NULL
        )
    ),
    -- Copilot entrypoint exp
    (
        "ab_beakman_native_cockpit_copilot_entry_point_experiment",
        named_struct(
            'begin_date', DATE('2025-03-11'),
            'end_date', NULL,
            'variants', to_json(
                named_struct(
                    'baseline', 'baseline',
                    'treatment', 'treatment'
                )
            ),
            'filters', NULL
        )
    ),
    -- Important exp from another team
    (
        "ab_beakman_wpp_alert",
        named_struct(
            'begin_date', DATE('2025-03-10'),
            'end_date', NULL,
            'variants', to_json(
                named_struct(
                    '0', 'baseline',
                    '1', 'treatment'
                )
            ),
            'filters', NULL
        )
    ),
    -- HUE VS HSE for Rent
    (
        "AB_TEST_RECS_HUE_ITEM_RENT",
        named_struct(
            'begin_date', DATE('2025-03-26'),
            'end_date', NULL,
            'variants', to_json(
                named_struct(
                    '0', 'baseline',
                    '1', 'treatment'
                )
            ),
            'filters', NULL
        )
    ),
    -- HUE VS HSE for Sale
    (
        "AB_TEST_RECS_HUE_ITEM_SALE",
        named_struct(
            'begin_date', DATE('2025-03-26'),
            'end_date', NULL,
            'variants', to_json(
                named_struct(
                    '0', 'baseline',
                    '1', 'treatment'
                )
            ),
            'filters', NULL
        )
    )
    -- Add new experiment here

AS experiment_config(experiment_name, config)
