import logging
from argparse import ArgumentParser
from multiprocessing.dummy import Pool

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.etl.transformer import Transformer
from bietlejuice.jobs.composer.base.spark import BaseSparkContext

sqlContext = BaseSparkContext.sqlContext

JOB_NAME = "create_external_tables"
NB_THREADS = 16

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

parser = ArgumentParser(description=JOB_NAME)
parser.add_argument("env")
parser.add_argument("datalake_layer")
parser.add_argument("source")
parser.add_argument("--tables", nargs="+", dest="tables", required=False)
parser.add_argument(
    "--all", nargs="?", dest="all", required=False, default=False, const=True
)


@logger
def create_external_table(args):
    transformer, datalake_layer, table_name = args
    transformer.create_athena_table(table_name, datalake_layer, overwrite=True)
    logger.info(
        "m=create_external_table, table={}, msg=Finished creating table.".format(
            table_name
        )
    )


if __name__ == "__main__":
    args = parser.parse_args()
    env = args.env
    datalake_layer = args.datalake_layer
    source = args.source
    tables = args.tables
    all = args.all

    logger.info(
        "m=__main__, env={}, datalake_layer={}, source={}, tables={}, all={}, msg=Job execution started".format(
            env, datalake_layer, source, tables, all
        )
    )

    transformer = Transformer(env, source)
    if all:
        logger.info(
            "m=__main__, tables=all, msg=Creating {} external tables...".format(
                datalake_layer
            )
        )
        tables = sqlContext.tableNames(
            dbName=transformer._get_spark_schema(datalake_layer)
        )
        with Pool(NB_THREADS) as p:
            p.map(
                create_external_table,
                [(transformer, datalake_layer, table) for table in tables],
            )
        logger.info(
            "m=__main__, tables=all, msg=External tables were created successfully."
        )
    elif tables:
        logger.info(
            "m=__main__, tables={}, msg=Creating {} external tables...".format(
                str(tables), datalake_layer
            )
        )
        with Pool(NB_THREADS) as p:
            p.map(
                create_external_table,
                [(transformer, datalake_layer, table) for table in tables],
            )
        logger.info(
            "m=__main__, tables={}, msg=External tables were created successfully.".format(
                str(tables)
            )
        )
    else:
        logger.warning(
            "m=__main__, msg=No tables or all flag passed, nothing to do.".format(
                str(tables), datalake_layer
            )
        )
