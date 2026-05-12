# Documentations Scripts

## generate_doc.py

The documentation generation script aims to add column descriptions in the lineage file of a table from a gsheet. With it we can create a gsheet to make our documentation more collaborative.

To generate the data frame that will be used to insert descriptions in the lineage file, we use a Databricks notebook. The Databricks notebook is responsible for creating the API instance and generating a dataframe from the passed gsheet.

* Important: This script must be run together with the notebook creating the data frame, with the notebook running before the local script.

### lib requirements:
    - yaml (pip3 install yaml);
    - pandas (pip3 install pandas);
    - databricks (pip3 install databricks-cli);

* Note 1: to be able to run the databricks-cli commands the proper settings must be done, you can check how to configure in this guide: https://docs.databricks.com/dev-tools/cli/
* Note 2: After configuring databricks-cli, when running it you may get an error like "databricks: command not found". To make the correction you can export the python path to the environment variable as follows: export PATH="......(path to your python library)/Library/Python/3.9/bin"

### How to run the script?

    1 - First we have to run the Databricks notebook(https://dbc-931ee6e0-6803.cloud.databricks.com/?o=4531937035440038#notebook/388410140231736/) that will generate our data frame, in which we will have the documentation in the notebook itself.

    2 - Then create a json file in the script folder itself, with the following structure:
    {
        "dag_name":
            {
                "line": "",
                "layer": "",
                "table": ""
            }
    }

    3 - Run the local script, which will ask for the name of the created json file.

    4 - Finally, check that the changes made to your lineage file are correct. With that done, just enjoy the time saved :)
