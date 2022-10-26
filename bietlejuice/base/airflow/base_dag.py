from os.path import join

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService

logger = QuintoAndarLogger("BaseDAG")


class BaseDAG:
    @staticmethod
    def get_dag_doc(dag_name, template_path=None):
        """
        :param dag_name: dag_name or tree_path to your doc.
        :type dag_name: str
        :param template_path: Used to bypass dag package path
            and set a path to a doc template.
        :type template_path: str, optional.
        :rtype: str
        """
        dag_path = DAGPackagesPathService.get_dag_path(dag_name)
        doc_md_string = ""
        dag_path = template_path if template_path else dag_path
        doc_file_path = join(dag_path, f"{dag_name}.md")

        try:
            doc_md_string = open(doc_file_path).read()
        except Exception as e:
            logger.info(
                f"m=BaseDAG.get_dag_doc, msg=The DAG doc file could not be opened, "
                f"dag_name={dag_name}, file_path={doc_file_path}"
            )
            raise e
        finally:
            return doc_md_string
