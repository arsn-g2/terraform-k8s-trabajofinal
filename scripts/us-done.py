#!/usr/bin/env python3
"""Mark a user story as completed (✅) or pending (⬜) in every place it is tracked.

Usage:
    scripts/us-done.py 16          # US-16 -> ✅
    scripts/us-done.py US-16 3     # several at once
    scripts/us-done.py --undo 16   # back to ⬜

Places updated:
  - the story's row in the fases.md tables (Completed column);
  - the story's row in its persona "Orden de trabajo" table;
  - the "**Completed:**" line under the story's heading (historias/*.md, or plan.md for US-43).
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILES = [ROOT / "fases.md", ROOT / "plan.md", *sorted((ROOT / "historias").glob("*.md"))]
DONE, TODO = "✅", "⬜"


def parse_id(arg: str) -> str:
    m = re.fullmatch(r"(?i)(?:us-?)?(\d{1,2})", arg.strip())
    if not m:
        sys.exit(f"Invalid story id: {arg!r} (use 16, 03 or US-16)")
    return f"{int(m.group(1)):02d}"


def update(num: str, old: str, new: str) -> int:
    row = re.compile(rf"^(\| (?:\d \| )?\[US-{num} · .*\| ){re.escape(old)}( \|)$", re.M)
    anchor = f'<a id="us-{num}"></a>'
    changes = 0
    for path in FILES:
        text = path.read_text(encoding="utf-8")
        new_text, n = row.subn(rf"\g<1>{new}\g<2>", text)
        changes += n
        # Completed line: the first "**Completed:**" within a few lines after the anchor.
        lines = new_text.split("\n")
        for i, line in enumerate(lines):
            if line.strip() == anchor:
                for j in range(i + 1, min(i + 5, len(lines))):
                    if lines[j].startswith(f"**Completed:** {old}"):
                        lines[j] = lines[j].replace(f"**Completed:** {old}", f"**Completed:** {new}", 1)
                        changes += 1
                        break
        new_text = "\n".join(lines)
        if new_text != text:
            path.write_text(new_text, encoding="utf-8")
            print(f"  {path.relative_to(ROOT)}")
    return changes


def main() -> None:
    args = sys.argv[1:]
    undo = "--undo" in args
    ids = [a for a in args if a != "--undo"]
    if not ids:
        sys.exit(__doc__)
    old, new = (DONE, TODO) if undo else (TODO, DONE)
    for num in map(parse_id, ids):
        print(f"US-{num}: {old} -> {new}")
        n = update(num, old, new)
        if n == 0:
            print(f"  nothing changed (US-{num} does not exist or is already {new})")
        else:
            print(f"  {n} marks updated")


if __name__ == "__main__":
    main()
