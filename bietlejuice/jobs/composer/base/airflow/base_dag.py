from glob import glob
from os import path
from datetime import timedelta
from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("BaseDAG")
COMPOSER_DAGS_PATH = path.abspath(path.join(__file__, "../../../dags"))


class BaseDAG:
    # TODO: Keep it until all Composer DAG owners are re-assigned
    DEFAULT_OWNER = "Data Engineering Team"
    OPERATOR_RETRIES = {
        "retries": 3,
        "retry_delay": timedelta(minutes=3),
        "max_retry_delay": timedelta(minutes=3),
    }
    EXECUTION_TIMEOUT = timedelta(hours=2)

    @staticmethod
    def get_dag_doc(dag_name):
        doc_md_string = ""
        file_path = glob(f"{COMPOSER_DAGS_PATH}/**/{dag_name}.md", recursive=True)
        try:
            if len(file_path) == 1:
                doc_md_string = open(file_path[0]).read()
            else:
                raise Exception(
                    f"The amount of files discovered for {dag_name} is {len(file_path)} and we expected to get 1"
                )
        except Exception as e:
            logger.info(f"m=get_dag_doc, msg=we found an issue for {dag_name}, e={e}")
        finally:
            return doc_md_string
