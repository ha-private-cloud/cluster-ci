import queue
import threading
from dataclasses import dataclass
from typing import Optional


@dataclass
class Build:
    id: str
    app_name: str
    tag: str
    status: str = "queued"  # queued | running | succeeded | failed
    stage: Optional[str] = None  # testing | building | deploying
    error: Optional[str] = None
    build_job_name: Optional[str] = None
    deploy_job_name: Optional[str] = None

    def to_dict(self) -> dict:
        return {
            "build_id": self.id,
            "app": self.app_name,
            "tag": self.tag,
            "status": self.status,
            "stage": self.stage,
            "error": self.error,
        }


class BuildQueue:
    """In-memory FIFO with a fixed pool of worker threads. Deliberately not
    distributed/persistent — this is a single-user homelab runner, and state
    living in one process's memory is why the Dockerfile runs gunicorn with
    a single worker process (multiple processes would each have their own
    queue and lose track of each other's builds)."""

    def __init__(self, job_runner, max_concurrent: int = 1):
        self._job_runner = job_runner
        self._pending: "queue.Queue[Build]" = queue.Queue()
        self._builds: dict[str, Build] = {}
        self._lock = threading.Lock()
        self._max_concurrent = max_concurrent

    def start(self) -> None:
        for _ in range(self._max_concurrent):
            threading.Thread(target=self._worker, daemon=True).start()

    def submit(self, build_id: str, app_name: str, tag: str) -> Build:
        build = Build(id=build_id, app_name=app_name, tag=tag)
        with self._lock:
            self._builds[build_id] = build
        self._pending.put(build)
        return build

    def get(self, build_id: str) -> Optional[Build]:
        with self._lock:
            return self._builds.get(build_id)

    def _worker(self) -> None:
        while True:
            build = self._pending.get()
            try:
                build.status = "running"
                self._job_runner.run_pipeline(build)
            except Exception as exc:  # noqa: BLE001 - report any failure back to the caller
                build.status = "failed"
                build.error = str(exc)
            finally:
                self._job_runner.cleanup(build)
                self._pending.task_done()
