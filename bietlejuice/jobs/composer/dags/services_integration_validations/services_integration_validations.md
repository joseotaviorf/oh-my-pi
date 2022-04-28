# Services-Integration Validations 

### Purpose

Simulate key communication/integration lines between services that compose our ELT jobs, to guarantee there is no failures in the pipeline (and early catch eventual failures).

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

- This DAG is supposed to be run in PROD.

- This DAG executes the Spark Job `run_validation_suites.py`, that wil run every **validation suite**
placed inside path `bietlejuice/jobs/composer/validation_suites/`.

- The validation suites must follow the pattern `/<dir_name>/<suite_name>_validation_suite.py`.
Example: `mysql_validation_suite.py`.

> The validation suites are testing/validating code that will run in the Spark jobs, in Databricks.
In one validation suite, you can define all the tests you would like to perform for a given suite context.
For example, in the _SortingHatValidationSuite_ class, you can define database access tests, auth test, DML tests, etc.


#### Executors

##### Concept

Executors are responsible for executing all the respective validation suites that inherit them.
Also, they may contain default and generic tests for a group of suites.

#### Validation Suites

#### Concept
A validation suite works like a python unit test class. You may define validation methods following the name pattern and these methods will be run.

Inside the validation suite you may define the REPOSITORY_CONSUMER_CLASS and validation methods you want to implement, for each source for example.
You are free to implement a custom validation inside your suite, but if this a common validation we may want to generalize it and use the DatabaseValidationSuitesExecutor for doing the validation.

The `validation_*` methods inside your suite and inside parent class `DatabaseValidationSuitesExecutor` will run automatically by the validation engine.

##### Default and custom validations
Every suite must inherit a `*ValidationSuitesExecutor` that contains *default* validations.
And if you want to run custom validation for your service, you can create a method with prefix `validation_`.

### Execution Interval

This DAG is triggered afternoon at 13h, 16h, 18h and 20h. 

</details>

#### This documentation is under development and will be enhanced and moved to DE Wiki in Notion
#### If you have doubts call Data Availability team
