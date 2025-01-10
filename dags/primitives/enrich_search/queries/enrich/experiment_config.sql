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
            -- add and sql expression to filter the experiment participants here
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
    -- ab_beakman_ranking_sale_pclick_v1
    (
        "ab_beakman_ranking_sale_pclick_v1",
        named_struct(
            'begin_date', DATE('2024-10-19'),
            'end_date', DATE('2025-01-01'),
            'variants', to_json(
                named_struct(
                    '0', 'baseline',
                    '1', 'treatment'
                )
            ),
            'filters', "business_context = 'sale'"
        )
    ),
    -- ab_beakman_search_services_demand_concentration_rent_experiment
    (
        "ab_beakman_search_services_demand_concentration_rent_experiment",
        named_struct(
            'begin_date', DATE('2024-12-19'),
            'end_date', NULL,
            'variants', to_json(
                named_struct(
                    '0', 'baseline',
                    '1', 'treatment'
                )
            ),
            'filters', "business_context = 'rent'"
        )
    ),
    -- AB_TEST_RECS_HUE_INDEXED_RENT
    (
        "AB_TEST_RECS_HUE_INDEXED_RENT",
        named_struct(
            'begin_date', DATE('2024-12-09'),
            'end_date', DATE('2025-01-09'),
            'variants', to_json(
                named_struct(
                    '0', 'baseline',
                    '1', 'treatment'
                )
            ),
            'filters', "business_context = 'rent'"
        )
    ),
    -- AB_TEST_RECS_HUE_INDEXED_SALE
    (
        "AB_TEST_RECS_HUE_INDEXED_SALE",
        named_struct(
            'begin_date', DATE('2024-12-09'),
            'end_date', DATE('2025-01-09'),
            'variants', to_json(
                named_struct(
                    '0', 'baseline',
                    '1', 'treatment'
                )
            ),
            'filters', "business_context = 'sale'"
        )
    ),
    -- Copilot exp
    (
        "native_copilot_experiment",
        named_struct(
            'begin_date', DATE('2024-11-07'),
            'end_date', DATE('2025-01-01'),
            'variants', to_json(
                named_struct(
                    'baseline', 'baseline',
                    'treatment', 'treatment'
                )
            ),
            'filters', NULL
        )
    )
    -- Add new experiment here

AS experiment_config(experiment_name, config)
