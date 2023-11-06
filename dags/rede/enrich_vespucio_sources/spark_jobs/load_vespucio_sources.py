"""
All the logic to load the sources from Vespucio into delta tables is self contained in the repository.
https://github.com/quintoandar/vespucio

This job is out of pattern, because there is currently no support for Delta, and Vespúcio is not exclusively an analytics initiative.
Nevertheless, once we get Delta support in bietlejuice, we should make some adjustments here.
"""

import os
import logging
import sys
from argparse import ArgumentParser
from vespucio.sources.jobs.sql import SQL_BASE_DIRECTORY
from vespucio.sources.jobs.sql.sql_job import SQLJob

logging.getLogger("py4j").setLevel(logging.ERROR)

def main() -> None:
    parser = ArgumentParser()
    parser.add_argument(
        "table_name",
        help=f"Table name. Eg. 'ebdb_condos'",
    )
    args = parser.parse_args()
    
    sql_file_name = f"{args.table_name}.sql"
    script_path = os.path.join(SQL_BASE_DIRECTORY, sql_file_name)
    if not os.path.exists(script_path):
        logging.error(f"Script file {script_path} does not exist.")
        files = os.listdir(SQL_BASE_DIRECTORY)
        logging.error(f"Did you mean: {', '.join(files)}?")
        sys.exit(1)

    SQLJob(args.table_name, script_path).main()


if __name__ == "__main__":
    main()