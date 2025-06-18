# airflow.clear_dataset_queue

## Short

This is a utility DAG that resets the dataset queue of your DAG, so that it is not affected from previous triggers.
This is often useful to make sure that runs from a previous day do not impact the execution of the pipeline in the following day.

## Long

Refer to the [Datasets user guide](https://docs.google.com/document/d/1dfTMqxDFV00uElPONo8a85m5dhpqnfHeBKNn48Kdcb8/edit?tab=t.0#heading=h.7mfa516ef9eo).