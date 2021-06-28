## GSHEETS_SEVERAL_DAILY_RUNS
​
### Purpose
​
This DAG extracts data from Google Sheets files. It may run several times a day.

This DAG has no dependency in Mediator so it can run several times a day. This is a palliative solution, until we evolve the Mediator to be able to handle it.

If you need information to understand how you can add your sheet, check our [Google Sheets Guide](https://www.notion.so/productquintoandar/Google-Sheets-0c11b1f13b7349918f91c0dec2b7e8f1).

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>
​
### Execution​ Interval

This DAG is trigged daily and it mays run many times in the same day.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following output tables:

1. Data lake raw:
    - All gsheets defined in `gsheets_several_daily_runs_files.yaml`, available [here](https://github.com/quintoandar/bi-etl-ejuice/blob/master/bietlejuice/jobs/composer/dags/gsheets/gsheets_files.yaml)

2. Data lake clean:
    - `photos_recovery_common_area_facade`

### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).

</details>