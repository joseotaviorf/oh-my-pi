from abc import ABC, abstractmethod


class AbstractPipeline(ABC):
    @abstractmethod
    def run(self):
        raise NotImplementedError()
