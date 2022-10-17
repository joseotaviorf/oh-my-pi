from glob import glob
from bietlejuice.dags import COMPOSER_DAGS_PATH
from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("BaseDAG")


class BaseDAG:
    @staticmethod
    def get_dag_doc(dag_name, root_path=None):
        doc_md_string = ""
        if root_path:
            DOC_ROOT_PATH = root_path
        else:
            DOC_ROOT_PATH = f"{COMPOSER_DAGS_PATH}/**"
        file_path = glob(f"{DOC_ROOT_PATH}/{dag_name}.md", recursive=True)
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
