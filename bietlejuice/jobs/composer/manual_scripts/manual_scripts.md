## Goal

This folder harbours scripts that runs outside our standard flow. To be here, this script 
must runs rarely.


## Tags

For while, tags will be updated manually, using the Atlas UI. We don't expect that
the amount of scripts of this type grows quickly, neither the amount of tables. 
In this way, an automation is not highly necessary, buut would be interesting.

## Current Content

### Scripts:
    - load_full_quintoandar_into_datalake.py:
        Load tables with potential common use among different contexts. From S3 to 
        the sync with Hive. These tables have queries stored in this [folder](https://github.com/quintoandar/bi-etl-ejuice/tree/master/bietlejuice/jobs/composer/db/datalake/queries/quintoandar).
    
    -load_full_public_into_dw.py:
        Load tables with potential common use among different contexts. From S3 to the sync with Hive. These tables have queries stored in this [folder](https://github.com/quintoandar/bi-etl-ejuice/tree/master/bietlejuice/jobs/composer/db/dw/queries/public).

### tables:
    - aux_date:
        A table that contains information about date ranging from 2010 to 2030.
        Currently, this table has the same columns of dim_date, but is available
        in the datalake.
    
    -dim_date:
        A table that contains information about date ranging from 2010 to 2030. Available
        in DW.