import shutil
import tarfile
from pathlib import Path

WORKSPACE_ROOT = Path("/workspace")


def save_upload(build_id: str, file_storage) -> Path:
    workspace = WORKSPACE_ROOT / build_id
    workspace.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=file_storage.stream, mode="r:gz") as tar:
        _safe_extract(tar, workspace)
    return workspace


def _safe_extract(tar: tarfile.TarFile, dest: Path) -> None:
    # tarfile.extractall follows member paths as-is; reject anything that
    # would escape `dest` (e.g. "../../etc/passwd") before extracting.
    dest_resolved = dest.resolve()
    for member in tar.getmembers():
        member_path = (dest / member.name).resolve()
        if dest_resolved not in member_path.parents and member_path != dest_resolved:
            raise ValueError(f"unsafe tar entry: {member.name}")
    tar.extractall(dest)


def cleanup_workspace(build_id: str) -> None:
    shutil.rmtree(WORKSPACE_ROOT / build_id, ignore_errors=True)
