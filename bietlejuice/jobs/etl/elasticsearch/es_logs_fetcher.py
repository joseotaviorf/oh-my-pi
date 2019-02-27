from abc import ABCMeta
from abc import abstractmethod
from elasticsearch import Elasticsearch
from qa_python_utils import QuintoAndarLogger

logger = QuintoAndarLogger('ESLogsFetcher')


class ESLogsFetcher(object):
    __metaclass__ = ABCMeta

    def __init__(self, es_logs__hostname):
        self.es = Elasticsearch(es_logs__hostname)
        self.index = None
        self.doc_type = None
        self.body = None

    @abstractmethod
    def build_query(self):
        raise NotImplementedError

    @abstractmethod
    def run(self):
        raise NotImplementedError

    @logger
    def __search(self, from_=0, size=10):
        result = self.es.search(
            index=self.index,
            doc_type=self.doc_type,
            body=self.body,
            from_=from_,
            size=size
        )
        return result

    @logger
    def __paginate_results(self, starting_from, total_size, step_size):
        for from_ in xrange(starting_from, total_size, step_size):
            # to fit a page with less then {step_size} results
            size = min(step_size, total_size - from_)
            search_result = self.__search(from_=from_, size=size)
            yield search_result

    @logger
    def fetch_all(self, step_size=10, max_size=None):
        # first search sets total amount of hits
        search_result = self.__search()
        logger.info('m=ESLogsFetcher.fetch_all, hits_total={}'.format(
            search_result['hits']['total']))
        total_size = min(search_result['hits']['total'], max_size)
        starting_from = 0

        logs = []
        iterator = self.__paginate_results(
            starting_from=starting_from,
            total_size=total_size,
            step_size=step_size
        )

        for log in iterator:
            hits = log['hits']['hits']
            logger.info(
                'm=ESLogsFetcher.fetch_all, msg=hits.length={}'.format(
                    len(hits)))
            logs += hits

        return logs
