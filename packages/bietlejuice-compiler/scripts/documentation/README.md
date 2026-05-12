# Documentation scripts

## copy_description.py

This script can be used to copy column description from an already complete metadata file to another one with missing
descriptions. The script will copy based on the lineage file and only columns with 1 column on the lineage property, so
calculated columns will be skipped, for example.
The script, by default, considers that we are copying the description backwards on the pipeline, for example:

 1. sale_offer to sale_offer_flows: sale_offer depends on sale_offer_flows in the lineage, so this is a backward copy;
 2. sale_offer to fact_offer: sale_offer is a dependency for fact_offer, so this is a forward copy.

  To use it you will need origin and destination dag and table names.

  The script will save the destination metadata file with the updated descriptions and the missing ones if existing.

  To run, use this command:

- For backward copy:

    `python3 copy_description.py -od <origin_dag> -ot <origin_table> -dd <destination_dag> -dt <destination_table>`

- For forward copy:

    `python3 copy_description.py -od <origin_dag> -ot <origin_table> -dd <destination_dag> -dt <destination_table> -f`
