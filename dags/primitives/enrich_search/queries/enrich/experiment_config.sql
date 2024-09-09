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
    -- ab_search_services_mono_pclick
    (
        "ab_search_services_mono_pclick",
        named_struct(
            'begin_date', DATE('2024-05-22'),
            'end_date', DATE('2024-06-01'),
            'variants', to_json(
                named_struct(
                    'baseline', 'baseline',
                    '0', 'baseline',
                    'treatment', 'treatment_1',
                    '1', 'treatment_1'
                )
            ),
            'filters', "business_context = 'rent'"
        )
    )
    -- Add new experiment here

AS experiment_config(experiment_name, config)
