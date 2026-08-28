"""Build safe, disposable SidePanel adaptations of standard Omarchy panels."""

from __future__ import annotations

import argparse
import errno
import fcntl
import hashlib
import json
import os
import re
import stat
import sys
import tempfile
import time
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator


class AdaptationError(Exception):
    """The source does not satisfy SidePanel's deliberately narrow contract."""


ADAPTER_VERSION = "side-panel-adapter-v2"
MAX_ENTRY_POINT_BYTES = 1024 * 1024
MAX_SOURCE_ENTRIES = 1024
MAX_SOURCE_FILES = 512
MAX_SOURCE_FILE_BYTES = 2 * 1024 * 1024
MAX_SOURCE_TREE_BYTES = 16 * 1024 * 1024
MAX_SOURCE_DEPTH = 128
MAX_MARKER_BYTES = 256 * 1024
COPY_CHUNK_BYTES = 64 * 1024
MAX_CACHED_ARTIFACTS = 8
STALE_STAGING_SECONDS = 24 * 60 * 60
MARKER_NAME = ".omarchy-side-panel-adapted"
HELPER_NAMES = ("SidePanelHost.qml", "SidePanelDisabledIpc.qml", "SidePanelHiddenBarButton.qml")


@dataclass(frozen=True)
class Token:
    value: str
    start: int
    end: int


@dataclass(frozen=True)
class ObjectNode:
    type_name: str
    type_token: Token
    open_token: Token
    close_token: Token


@dataclass
class TreeBudget:
    entries: int = 0
    files: int = 0
    bytes: int = 0


def tokens(source: str) -> list[Token]:
    """Return QML syntax tokens while deliberately ignoring comments and strings."""
    result: list[Token] = []
    index = 0
    size = len(source)
    while index < size:
        current = source[index]
        if current.isspace():
            index += 1
        elif source.startswith("//", index):
            newline = source.find("\n", index + 2)
            index = size if newline < 0 else newline + 1
        elif source.startswith("/*", index):
            end = source.find("*/", index + 2)
            if end < 0:
                raise AdaptationError("unterminated block comment")
            index = end + 2
        elif current in "\"'`":
            quote = current
            index += 1
            while index < size:
                if source[index] == "\\":
                    index += 2
                elif source[index] == quote:
                    index += 1
                    break
                else:
                    index += 1
            else:
                raise AdaptationError("unterminated string")
        elif current.isalpha() or current == "_":
            start = index
            index += 1
            while index < size and (source[index].isalnum() or source[index] == "_"):
                index += 1
            result.append(Token(source[start:index], start, index))
        else:
            result.append(Token(current, index, index + 1))
            index += 1
    return result


def object_nodes(token_list: list[Token]) -> list[ObjectNode]:
    """Recognize QML object blocks; JavaScript blocks do not have a type token."""
    stack: list[tuple[Token, Token]] = []
    nodes: list[ObjectNode] = []
    for index, token in enumerate(token_list):
        if token.value == "{" and index > 0:
            previous = token_list[index - 1]
            if previous.value and (previous.value[0].isalpha() or previous.value[0] == "_"):
                stack.append((previous, token))
            else:
                stack.append((Token("", token.start, token.start), token))
        elif token.value == "{":
            stack.append((Token("", token.start, token.start), token))
        elif token.value == "}":
            if not stack:
                raise AdaptationError("unmatched closing brace")
            type_token, open_token = stack.pop()
            if type_token.value:
                nodes.append(ObjectNode(type_token.value, type_token, open_token, token))
    if stack:
        raise AdaptationError("unmatched opening brace")
    return sorted(nodes, key=lambda node: node.open_token.start)


def direct_property(token_list: list[Token], node: ObjectNode, name: str) -> tuple[Token, Token] | None:
    """Find a direct `name: value` binding in an object, not a nested object."""
    depth = 0
    for index, token in enumerate(token_list):
        if token.start <= node.open_token.start or token.end >= node.close_token.end:
            continue
        if token.value == "{":
            depth += 1
        elif token.value == "}":
            depth -= 1
        elif depth == 0 and token.value == name and index + 1 < len(token_list):
            colon = token_list[index + 1]
            if colon.value == ":":
                return token, colon
    return None


def direct_id(token_list: list[Token], node: ObjectNode) -> str:
    binding = direct_property(token_list, node, "id")
    if binding is None:
        raise AdaptationError("root Panel must declare an id")
    _, colon = binding
    try:
        value = token_list[token_list.index(colon) + 1]
    except IndexError as error:
        raise AdaptationError("root Panel has an incomplete id") from error
    if not value.value or not (value.value[0].isalpha() or value.value[0] == "_"):
        raise AdaptationError("root Panel id must be an identifier")
    return value.value


def contains(node: ObjectNode, child: ObjectNode) -> bool:
    return node.open_token.start < child.open_token.start < node.close_token.end


def replace_ranges(source: str, replacements: list[tuple[int, int, str]]) -> str:
    chunks: list[str] = []
    cursor = 0
    for start, end, value in sorted(replacements):
        if start < cursor or end < start or end > len(source):
            raise AdaptationError("overlapping or invalid source transformation")
        chunks.extend((source[cursor:start], value))
        cursor = end
    chunks.append(source[cursor:])
    return "".join(chunks)


def transform_qml(source: str) -> str:
    """Adapt one constrained standard panel source without rewriting its lifecycle."""
    token_list = tokens(source)
    nodes = object_nodes(token_list)
    if not nodes or nodes[0].type_name != "Panel":
        raise AdaptationError("the root object must be a standard Panel")
    root = nodes[0]
    root_id = direct_id(token_list, root)

    for unsupported in ("PanelWindow", "PopupWindow", "FloatingWindow"):
        if any(node.type_name == unsupported and contains(root, node) for node in nodes):
            raise AdaptationError(f"unsupported mapped surface: {unsupported}")

    hosts = [node for node in nodes if node.type_name == "KeyboardPanel" and contains(root, node)]
    if len(hosts) != 1:
        raise AdaptationError("expected exactly one standard KeyboardPanel")
    host = hosts[0]

    if direct_property(token_list, root, "sidePanelHost"):
        raise AdaptationError("root Panel already declares sidePanelHost")
    if direct_property(token_list, host, "sidePanelHost") or direct_property(token_list, host, "page"):
        raise AdaptationError("KeyboardPanel uses reserved SidePanel host properties")

    replacements: list[tuple[int, int, str]] = [
        (
            root.open_token.end,
            root.open_token.end,
            "\n  property var sidePanelHost: null"
            "\n  property var sidePanelFocusTarget: null"
            "\n  function sidePanelFocus() { if (sidePanelFocusTarget) sidePanelFocusTarget.forceActiveFocus() }",
        ),
        (host.type_token.start, host.type_token.end, "SidePanelHost"),
        (
            host.open_token.end,
            host.open_token.end,
            f"\n    anchors.fill: parent\n    sidePanelHost: {root_id}.sidePanelHost\n    page: {root_id}"
            f"\n    onFocusTargetChanged: {root_id}.sidePanelFocusTarget = focusTarget"
            f"\n    Component.onCompleted: {root_id}.sidePanelFocusTarget = focusTarget",
        ),
    ]

    manage_ipc = direct_property(token_list, root, "manageIpc")
    if manage_ipc is None:
        replacements.append((root.open_token.end, root.open_token.end, "\n  manageIpc: false"))
    else:
        _, colon = manage_ipc
        value_index = token_list.index(colon) + 1
        if value_index >= len(token_list) or token_list[value_index].value not in ("true", "false"):
            raise AdaptationError("manageIpc must be a literal boolean")
        value = token_list[value_index]
        replacements.append((value.start, value.end, "false"))

    for node in nodes:
        if not contains(root, node):
            continue
        if node.type_name == "IpcHandler":
            replacements.append((node.type_token.start, node.type_token.end, "SidePanelDisabledIpc"))
        elif node.type_name in ("BarIconButton", "WidgetButton"):
            replacements.append((node.type_token.start, node.type_token.end, "SidePanelHiddenBarButton"))

    return replace_ranges(source, replacements)


def digest_field(digest: "hashlib._Hash", value: bytes) -> None:
    digest.update(len(value).to_bytes(8, "big"))
    digest.update(value)


def digest_entry(
    digest: "hashlib._Hash", kind: bytes, relative: Path, mode: int, size: int, content_digest: bytes = b""
) -> None:
    digest_field(digest, kind)
    digest_field(digest, relative.as_posix().encode("utf-8", "surrogateescape"))
    digest_field(digest, stat.S_IMODE(mode).to_bytes(4, "big"))
    digest_field(digest, size.to_bytes(8, "big"))
    digest_field(digest, content_digest)


def open_tree_entry(parent_descriptor: int, name: str, relative: Path) -> int:
    flags = os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC
    if not hasattr(os, "O_NOFOLLOW"):
        raise AdaptationError("O_NOFOLLOW is unavailable")
    try:
        return os.open(name, flags | os.O_NOFOLLOW, dir_fd=parent_descriptor)
    except OSError as error:
        if error.errno in (errno.ELOOP, errno.EMLINK):
            raise AdaptationError(f"source contains a symlink: {relative}") from error
        raise


def walk_tree(
    source_descriptor: int,
    relative_dir: Path,
    digest: "hashlib._Hash",
    budget: TreeBudget,
    target_dir: Path | None,
    skipped_root_names: frozenset[str],
    depth: int = 0,
) -> None:
    names: list[str] = []
    with os.scandir(source_descriptor) as iterator:
        for entry in iterator:
            if relative_dir == Path() and entry.name in skipped_root_names:
                continue
            names.append(entry.name)
            if budget.entries + len(names) > MAX_SOURCE_ENTRIES:
                raise AdaptationError("source contains too many entries")

    for name in sorted(names):
        if budget.entries >= MAX_SOURCE_ENTRIES:
            raise AdaptationError("source contains too many entries")
        relative = relative_dir / name
        descriptor = open_tree_entry(source_descriptor, name, relative)
        try:
            metadata = os.fstat(descriptor)
            budget.entries += 1
            if stat.S_ISDIR(metadata.st_mode):
                if depth >= MAX_SOURCE_DEPTH:
                    raise AdaptationError("source tree is too deeply nested")
                digest_entry(digest, b"directory", relative, metadata.st_mode, 0)
                child_target = target_dir / name if target_dir is not None else None
                if child_target is not None:
                    child_target.mkdir(mode=0o700)
                walk_tree(descriptor, relative, digest, budget, child_target, skipped_root_names, depth + 1)
                continue
            if not stat.S_ISREG(metadata.st_mode):
                raise AdaptationError(f"source contains an unsupported file: {relative}")

            budget.files += 1
            if budget.files > MAX_SOURCE_FILES:
                raise AdaptationError("source contains too many files")
            if metadata.st_size > MAX_SOURCE_FILE_BYTES:
                raise AdaptationError(f"source file exceeds maximum size: {relative}")

            output_descriptor = -1
            if target_dir is not None:
                output_descriptor = os.open(
                    target_dir / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC, 0o600
                )
            file_digest = hashlib.sha256()
            file_bytes = 0
            try:
                while chunk := os.read(descriptor, COPY_CHUNK_BYTES):
                    file_bytes += len(chunk)
                    budget.bytes += len(chunk)
                    if file_bytes > MAX_SOURCE_FILE_BYTES or budget.bytes > MAX_SOURCE_TREE_BYTES:
                        raise AdaptationError("source tree exceeds maximum size while copying")
                    file_digest.update(chunk)
                    if output_descriptor >= 0:
                        view = memoryview(chunk)
                        while view:
                            written = os.write(output_descriptor, view)
                            view = view[written:]
            finally:
                if output_descriptor >= 0:
                    os.close(output_descriptor)

            if target_dir is not None:
                (target_dir / name).chmod(0o600 | (stat.S_IMODE(metadata.st_mode) & 0o111))
            digest_entry(digest, b"file", relative, metadata.st_mode, file_bytes, file_digest.digest())
        finally:
            os.close(descriptor)


def tree_digest(source_dir: Path, target_dir: Path | None = None, skip_marker: bool = False) -> str:
    flags = os.O_RDONLY | os.O_CLOEXEC
    if hasattr(os, "O_DIRECTORY"):
        flags |= os.O_DIRECTORY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(source_dir, flags)
    except OSError as error:
        raise AdaptationError(f"cannot safely open source directory: {source_dir}") from error
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISDIR(metadata.st_mode):
            raise AdaptationError("source directory does not exist")
        if target_dir is not None:
            target_dir.mkdir(mode=0o700)
        digest = hashlib.sha256()
        walk_tree(
            descriptor,
            Path(),
            digest,
            TreeBudget(),
            target_dir,
            frozenset((MARKER_NAME,)) if skip_marker else frozenset(),
        )
        return digest.hexdigest()
    finally:
        os.close(descriptor)


def source_tree_digest(source_dir: Path, entries: object | None = None) -> str:
    """Hash the bytes and modes actually read from a bounded, symlink-free tree."""
    del entries
    return tree_digest(source_dir)


def read_entry_point(source: Path) -> str:
    """Read one QML entry point without allocating more than its fixed limit."""
    content = read_regular_file(source, MAX_ENTRY_POINT_BYTES, "entry point")
    if len(content) > MAX_ENTRY_POINT_BYTES:
        raise AdaptationError("entry point exceeds maximum size")
    try:
        return content.decode("utf-8")
    except UnicodeDecodeError as error:
        raise AdaptationError("entry point is not valid UTF-8") from error


def choose_source(source_dir: Path, entry_point: str) -> Path:
    entry = Path(entry_point)
    if entry.is_absolute() or ".." in entry.parts:
        raise AdaptationError("entry point is outside its plugin directory")
    candidate = (source_dir / entry).resolve()
    if not candidate.is_file() or source_dir not in candidate.parents:
        raise AdaptationError("entry point is outside its plugin directory")
    source = candidate
    if not has_standard_host(read_entry_point(source)):
        sibling = (candidate.parent / "Panel.qml").resolve()
        if sibling.is_file() and source_dir in sibling.parents:
            source = sibling
    return source


def has_standard_host(source: str) -> bool:
    return any(node.type_name == "KeyboardPanel" for node in object_nodes(tokens(source)))


def copy_tree(source_dir: Path, target_dir: Path) -> str:
    """Copy and hash one descriptor-based snapshot of a plugin source tree."""
    return tree_digest(source_dir, target_dir)


def is_within(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


RELATIVE_IMPORT = re.compile(
    r'(?m)^(?P<prefix>\s*import\s+)(?P<quote>["\'])(?P<path>[^"\']+)(?P=quote)(?P<suffix>\s+as\s+\w+)?\s*$'
)


def rebase_external_relative_imports(source: str, source_dir: Path, entry_source: Path) -> str:
    """Keep QML imports outside a copied plugin pointed at their original directory."""

    def replace(match: re.Match[str]) -> str:
        relative = match.group("path")
        if not relative.startswith("."):
            return match.group(0)
        target = (entry_source.parent / relative).resolve()
        if not target.is_dir() or is_within(target, source_dir):
            return match.group(0)
        return f'{match.group("prefix")}{match.group("quote")}{target.as_uri()}{match.group("quote")}{match.group("suffix") or ""}'

    return RELATIVE_IMPORT.sub(replace, source)


def read_regular_file(path: Path, maximum: int, label: str) -> bytes:
    flags = os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise AdaptationError(f"cannot safely open {label}: {path}") from error
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode):
            raise AdaptationError(f"{label} is not a regular file")
        if metadata.st_size > maximum:
            raise AdaptationError(f"{label} exceeds maximum size")
        chunks: list[bytes] = []
        remaining = maximum + 1
        while remaining > 0:
            chunk = os.read(descriptor, min(COPY_CHUNK_BYTES, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        content = b"".join(chunks)
        if len(content) > maximum:
            raise AdaptationError(f"{label} exceeds maximum size")
        return content
    finally:
        os.close(descriptor)


def safe_directory(path: Path) -> None:
    if not path.is_absolute() or path != Path(os.path.abspath(path)):
        raise AdaptationError(f"cache path must be absolute and normalized: {path}")
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    if path.resolve() != path:
        raise AdaptationError(f"refusing a cache path with symlinked ancestors: {path}")
    metadata = path.lstat()
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        raise AdaptationError(f"cache path is not a directory: {path}")
    if metadata.st_uid != os.getuid():
        raise AdaptationError(f"cache path is not owned by the current user: {path}")
    path.chmod(0o700)

    ancestor = path.parent
    while True:
        metadata = ancestor.lstat()
        if stat.S_ISLNK(metadata.st_mode):
            raise AdaptationError(f"refusing a symlinked cache ancestor: {ancestor}")
        if metadata.st_uid not in (0, os.getuid()):
            raise AdaptationError(f"refusing an untrusted cache ancestor: {ancestor}")
        writable_by_others = stat.S_IMODE(metadata.st_mode) & (stat.S_IWGRP | stat.S_IWOTH)
        if writable_by_others and not metadata.st_mode & stat.S_ISVTX:
            raise AdaptationError(f"refusing an insecure cache ancestor: {ancestor}")
        if ancestor == ancestor.parent:
            break
        ancestor = ancestor.parent


@contextmanager
def cache_lock(namespace_root: Path) -> Iterator[None]:
    lock_path = namespace_root / ".lock"
    flags = os.O_RDWR | os.O_CREAT | os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(lock_path, flags, 0o600)
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid():
            raise AdaptationError("cache lock is unsafe")
        os.fchmod(descriptor, 0o600)
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        os.close(descriptor)


def remove_tree_entry(parent_descriptor: int, name: str) -> None:
    try:
        metadata = os.stat(name, dir_fd=parent_descriptor, follow_symlinks=False)
    except FileNotFoundError:
        return
    if not stat.S_ISDIR(metadata.st_mode):
        os.unlink(name, dir_fd=parent_descriptor)
        return

    flags = os.O_RDONLY | os.O_CLOEXEC
    if hasattr(os, "O_DIRECTORY"):
        flags |= os.O_DIRECTORY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(name, flags, dir_fd=parent_descriptor)
    try:
        os.fchmod(descriptor, 0o700)
        for child in os.listdir(descriptor):
            remove_tree_entry(descriptor, child)
    finally:
        os.close(descriptor)
    os.rmdir(name, dir_fd=parent_descriptor)


def remove_tree(path: Path) -> None:
    flags = os.O_RDONLY | os.O_CLOEXEC
    if hasattr(os, "O_DIRECTORY"):
        flags |= os.O_DIRECTORY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    parent_descriptor = os.open(path.parent, flags)
    try:
        remove_tree_entry(parent_descriptor, path.name)
    finally:
        os.close(parent_descriptor)


def seal_tree(path: Path) -> None:
    for directory, _, files in os.walk(path, topdown=False, followlinks=False):
        directory_path = Path(directory)
        for name in files:
            file_path = directory_path / name
            metadata = file_path.lstat()
            if not stat.S_ISREG(metadata.st_mode):
                raise AdaptationError(f"generated artifact contains an unsafe file: {file_path}")
            file_path.chmod(0o400 | (stat.S_IMODE(metadata.st_mode) & 0o111))
        directory_path.chmod(0o700)


def clean_stale_staging(staging_parent: Path) -> None:
    cutoff = time.time() - STALE_STAGING_SECONDS
    for child in staging_parent.iterdir():
        try:
            metadata = child.lstat()
            if metadata.st_mtime >= cutoff:
                continue
            if stat.S_ISDIR(metadata.st_mode):
                active_lock = child / ".active"
                lock_descriptor = -1
                try:
                    flags = os.O_RDWR | os.O_CLOEXEC
                    if hasattr(os, "O_NOFOLLOW"):
                        flags |= os.O_NOFOLLOW
                    lock_descriptor = os.open(active_lock, flags)
                    fcntl.flock(lock_descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except FileNotFoundError:
                    pass
                except BlockingIOError:
                    continue
                try:
                    remove_tree(child)
                finally:
                    if lock_descriptor >= 0:
                        os.close(lock_descriptor)
            else:
                remove_tree(child)
        except OSError:
            continue


def prune_namespace(namespace_root: Path, current: Path) -> None:
    artifacts: list[tuple[float, Path]] = []
    for child in namespace_root.iterdir():
        if child == current or child.name == ".lock":
            continue
        try:
            metadata = child.lstat()
        except OSError:
            continue
        if stat.S_ISDIR(metadata.st_mode) and not stat.S_ISLNK(metadata.st_mode):
            artifacts.append((metadata.st_mtime, child))
        elif stat.S_ISLNK(metadata.st_mode):
            remove_tree(child)
    artifacts.sort(reverse=True)
    for _, artifact in artifacts[MAX_CACHED_ARTIFACTS - 1 :]:
        try:
            remove_tree(artifact)
        except OSError:
            continue


def completed_artifact(destination: Path, generated_source: Path, fingerprint: str) -> bool:
    marker = destination / MARKER_NAME
    try:
        if destination.is_symlink() or not destination.is_dir() or not is_within(generated_source, destination):
            return False
        document = json.loads(read_regular_file(marker, MAX_MARKER_BYTES, "artifact marker").decode("utf-8"))
        if not isinstance(document, dict):
            return False
        relative_source = generated_source.relative_to(destination).as_posix()
        if set(document) != {"version", "fingerprint", "entryPoint", "artifactDigest"}:
            return False
        if document["version"] != ADAPTER_VERSION or document["fingerprint"] != fingerprint:
            return False
        if document["entryPoint"] != relative_source:
            return False
        if not re.fullmatch(r"[0-9a-f]{64}", str(document["artifactDigest"])):
            return False
        return tree_digest(destination, skip_marker=True) == document["artifactDigest"]
    except (AdaptationError, KeyError, OSError, UnicodeError, ValueError, json.JSONDecodeError):
        return False


def build(source_dir: Path, entry_point: str, cache_root: Path, plugin_id: str, adapter_dir: Path) -> Path:
    source_dir = source_dir.resolve()
    adapter_dir = adapter_dir.resolve()
    cache_root = Path(cache_root)
    if not source_dir.is_dir():
        raise AdaptationError("source directory does not exist")
    if not adapter_dir.is_dir():
        raise AdaptationError("adapter directory does not exist")
    if not plugin_id or len(plugin_id) > 160 or plugin_id in (".", "..") or "/" in plugin_id:
        raise AdaptationError("plugin id is unsafe")
    if any(ord(character) < 32 for character in plugin_id):
        raise AdaptationError("plugin id is unsafe")
    if not cache_root.is_absolute() or cache_root != Path(os.path.abspath(cache_root)):
        raise AdaptationError("cache root must be an absolute normalized path")
    if is_within(cache_root, source_dir) or is_within(source_dir, cache_root):
        raise AdaptationError("cache root must not overlap the source plugin")

    safe_directory(cache_root)
    namespace = hashlib.sha256(plugin_id.encode("utf-8")).hexdigest()
    namespace_root = cache_root / namespace
    safe_directory(namespace_root)
    staging_parent = cache_root / ".staging"
    safe_directory(staging_parent)
    clean_stale_staging(staging_parent)
    staging = Path(tempfile.mkdtemp(prefix="adapter-", dir=staging_parent))
    staging.chmod(0o700)
    staging_lock = os.open(staging / ".active", os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC, 0o600)
    fcntl.flock(staging_lock, fcntl.LOCK_EX)
    try:
        output = staging / "output"
        copy_tree(source_dir, output)
        entry_source = choose_source(output, entry_point)
        entry_relative = entry_source.relative_to(output)
        original_entry_source = source_dir / entry_relative
        source = rebase_external_relative_imports(read_entry_point(entry_source), source_dir, original_entry_source)
        transformed = transform_qml(source).encode("utf-8")
        entry_source.chmod(0o600 | (entry_source.stat().st_mode & 0o111))
        entry_source.write_bytes(transformed)

        for helper in HELPER_NAMES:
            source_helper = adapter_dir / helper
            helper_target = entry_source.parent / helper
            if helper_target.exists() or helper_target.is_symlink():
                raise AdaptationError(f"plugin source collides with adapter helper: {helper}")
            helper_target.write_bytes(read_regular_file(source_helper, MAX_ENTRY_POINT_BYTES, f"adapter helper {helper}"))
            helper_target.chmod(0o600)

        seal_tree(output)
        artifact_digest = tree_digest(output)
        identity = "\0".join((ADAPTER_VERSION, str(source_dir), entry_relative.as_posix(), artifact_digest))
        fingerprint = hashlib.sha256(identity.encode("utf-8")).hexdigest()
        destination = namespace_root / fingerprint
        generated_source = destination / entry_relative
        marker = {
            "version": ADAPTER_VERSION,
            "fingerprint": fingerprint,
            "entryPoint": entry_relative.as_posix(),
            "artifactDigest": artifact_digest,
        }
        output.chmod(0o700)
        marker_path = output / MARKER_NAME
        marker_path.write_text(json.dumps(marker, sort_keys=True, separators=(",", ":")) + "\n")
        marker_path.chmod(0o400)

        with cache_lock(namespace_root):
            if destination.exists() or destination.is_symlink():
                if completed_artifact(destination, generated_source, fingerprint):
                    return generated_source
                remove_tree(destination)
            os.rename(output, destination)
            destination.chmod(0o700)
            if not completed_artifact(destination, generated_source, fingerprint):
                remove_tree(destination)
                raise AdaptationError("adapter publication failed integrity verification")
            prune_namespace(namespace_root, destination)
    finally:
        os.close(staging_lock)
        try:
            remove_tree(staging)
        except OSError:
            pass
    return generated_source


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_dir")
    parser.add_argument("entry_point")
    parser.add_argument("cache_root")
    parser.add_argument("plugin_id")
    parser.add_argument("adapter_dir")
    arguments = parser.parse_args()
    try:
        output = build(
            Path(arguments.source_dir),
            arguments.entry_point,
            Path(arguments.cache_root),
            arguments.plugin_id,
            Path(arguments.adapter_dir),
        )
    except AdaptationError as error:
        print(f"omarchy-side-panel-adapt: {error}", file=sys.stderr)
        return 1
    except OSError as error:
        print(f"omarchy-side-panel-adapt: filesystem error: {error}", file=sys.stderr)
        return 1
    print(output.as_uri())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
