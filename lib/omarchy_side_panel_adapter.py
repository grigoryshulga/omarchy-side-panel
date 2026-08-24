"""Build safe, disposable SidePanel adaptations of standard Omarchy panels."""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import shutil
import stat
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


class AdaptationError(Exception):
    """The source does not satisfy SidePanel's deliberately narrow contract."""


ADAPTER_VERSION = "side-panel-adapter-v1"


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
    result = source
    for start, end, value in sorted(replacements, reverse=True):
        result = result[:start] + value + result[end:]
    return result


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


def source_tree_digest(source_dir: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(source_dir.rglob("*")):
        relative = path.relative_to(source_dir)
        metadata = path.lstat()
        if stat.S_ISLNK(metadata.st_mode):
            raise AdaptationError(f"source contains a symlink: {relative}")
        if path.is_dir():
            digest.update(f"D:{relative}\n".encode())
        elif path.is_file():
            digest.update(f"F:{relative}\0".encode())
            with path.open("rb") as file:
                for chunk in iter(lambda: file.read(1024 * 1024), b""):
                    digest.update(chunk)
        else:
            raise AdaptationError(f"source contains an unsupported file: {relative}")
    return digest.hexdigest()


def choose_source(source_dir: Path, entry_point: str) -> Path:
    entry = Path(entry_point)
    if entry.is_absolute() or ".." in entry.parts:
        raise AdaptationError("entry point is outside its plugin directory")
    candidate = (source_dir / entry).resolve()
    if not candidate.is_file() or source_dir not in candidate.parents:
        raise AdaptationError("entry point is outside its plugin directory")
    source = candidate
    if not has_standard_host(source.read_text(encoding="utf-8")):
        sibling = (source_dir / "Panel.qml").resolve()
        if sibling.is_file() and source_dir in sibling.parents:
            source = sibling
    return source


def has_standard_host(source: str) -> bool:
    return any(node.type_name == "KeyboardPanel" for node in object_nodes(tokens(source)))


def copy_tree(source_dir: Path, target_dir: Path) -> None:
    shutil.copytree(source_dir, target_dir, symlinks=True, copy_function=shutil.copy2)


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


def safe_directory(path: Path) -> None:
    if path.exists() and path.is_symlink():
        raise AdaptationError(f"refusing a symlinked cache path: {path}")
    path.mkdir(parents=True, exist_ok=True)
    if not path.is_dir() or path.is_symlink():
        raise AdaptationError(f"cache path is not a directory: {path}")


def completed_artifact(destination: Path, generated_source: Path, fingerprint: str) -> bool:
    marker = destination / ".omarchy-side-panel-adapted"
    if destination.is_symlink() or generated_source.is_symlink() or marker.is_symlink():
        return False
    if not destination.is_dir() or not generated_source.is_file() or not marker.is_file():
        return False
    return marker.read_text(encoding="utf-8") == f"{ADAPTER_VERSION}\n{fingerprint}\n"


def build(source_dir: Path, entry_point: str, cache_root: Path, plugin_id: str, adapter_dir: Path) -> Path:
    source_dir = source_dir.resolve()
    adapter_dir = adapter_dir.resolve()
    cache_root = Path(os.path.abspath(cache_root))
    if not source_dir.is_dir():
        raise AdaptationError("source directory does not exist")
    if not adapter_dir.is_dir():
        raise AdaptationError("adapter directory does not exist")
    if not plugin_id or plugin_id in (".", "..") or "/" in plugin_id:
        raise AdaptationError("plugin id is unsafe")
    resolved_cache_root = cache_root.resolve()
    if cache_root != resolved_cache_root:
        raise AdaptationError("refusing a cache root with symlinked ancestors")
    cache_root = resolved_cache_root
    if is_within(cache_root, source_dir) or is_within(source_dir, cache_root):
        raise AdaptationError("cache root must not overlap the source plugin")

    entry_source = choose_source(source_dir, entry_point)
    source_digest = source_tree_digest(source_dir)
    source = rebase_external_relative_imports(entry_source.read_text(encoding="utf-8"), source_dir, entry_source)
    transformed = transform_qml(source)
    namespace = hashlib.sha256(plugin_id.encode("utf-8")).hexdigest()[:24]
    fingerprint = hashlib.sha256((source_digest + "\0" + ADAPTER_VERSION).encode()).hexdigest()[:24]
    destination = cache_root / namespace / fingerprint
    generated_source = destination / entry_source.relative_to(source_dir)
    safe_directory(cache_root)
    namespace_root = cache_root / namespace
    safe_directory(namespace_root)
    if destination.exists() or destination.is_symlink():
        if completed_artifact(destination, generated_source, fingerprint):
            return generated_source
        raise AdaptationError("existing cache destination is not a SidePanel artifact")

    staging_parent = cache_root / ".staging"
    safe_directory(staging_parent)
    staging = Path(tempfile.mkdtemp(prefix="adapter-", dir=staging_parent))
    try:
        output = staging / "output"
        copy_tree(source_dir, output)
        target = output / entry_source.relative_to(source_dir)
        target.chmod(target.stat().st_mode | stat.S_IWUSR)
        target.write_text(transformed, encoding="utf-8")
        for helper in ("SidePanelHost.qml", "SidePanelDisabledIpc.qml", "SidePanelHiddenBarButton.qml"):
            source_helper = adapter_dir / helper
            if not source_helper.is_file():
                raise AdaptationError(f"adapter helper is missing: {helper}")
            shutil.copy2(source_helper, output / helper)
        (output / ".omarchy-side-panel-adapted").write_text(
            f"{ADAPTER_VERSION}\n{fingerprint}\n", encoding="utf-8"
        )

        try:
            os.rename(output, destination)
        except FileExistsError:
            pass
    finally:
        shutil.rmtree(staging, ignore_errors=True)
    if not completed_artifact(destination, generated_source, fingerprint):
        raise AdaptationError("adapter publication failed")
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
