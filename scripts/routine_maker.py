#!/usr/bin/env python3
"""Outer Loop Routine Maker for Grok Bot Agent Factory.

Inspects patterns that have reached the repetition threshold, generates
the mandatory Receipt of Causality according to ADR 0001, and prepares
focused pull requests to evolve skills.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

from scripts.memory_store import get_ready_patterns, memory_lock, resolve_memory_dir


def load_lessons(mem_dir: Path) -> Dict[str, Dict[str, Any]]:
    """Loads all lessons from lessons.jsonl into a dictionary keyed by lesson ID."""
    lessons_file = mem_dir / "lessons.jsonl"
    lessons = {}
    if not lessons_file.exists():
        return lessons

    with open(lessons_file, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            record = json.loads(line)
            lessons[record["id"]] = record
    return lessons


def generate_receipt_of_causality(
    pattern: Dict[str, Any],
    lessons_map: Dict[str, Dict[str, Any]],
) -> str:
    """Formats the mandatory Receipt of Causality for human review per ADR 0001."""
    target_skill = pattern.get("targetSkill", "unknown")
    failure_class = pattern.get("failureClass", "unknown")
    count = pattern.get("count", 0)
    rubrics = ", ".join(pattern.get("rubricsViolated", [])) or "unspecified"

    lines = [
        "## Receipt of Causality",
        f"- **Target Skill**: `{target_skill}`",
        f"- **Failure Class**: `{failure_class}`",
        f"- **Repetition Count**: `{count}`",
        f"- **Rubrics Addressed**: `{rubrics}`",
        "- **Contributing Lessons**:",
    ]

    for lid in pattern.get("lessonIds", []):
        lesson = lessons_map.get(lid, {})
        summary = lesson.get("evidenceSummary", "No summary available")
        work_item = lesson.get("workItemId", "unknown")
        lines.append(f"  - `{lid}` ({work_item}): {summary}")

    lines.extend([
        "- **Expected Behavioral Change**:",
        f"  - Modifies `.agents/skills/{target_skill}/SKILL.md` to prevent recurring `{failure_class}` defects.",
        "",
        "> [!IMPORTANT]",
        "> Per ADR 0001, self-evolution pull requests modifying skills or factory rules require explicit human review and approval. Auto-merge is strictly disabled.",
    ])

    return "\n".join(lines)


def mark_pattern_synthesized(mem_dir: Path, pattern_id: str, routine_id: str) -> None:
    """Updates pattern index entry status to routine_synthesized."""
    patterns_file = mem_dir / "patterns.json"
    if not patterns_file.exists():
        return

    with memory_lock(mem_dir):
        with open(patterns_file, "r", encoding="utf-8") as pf:
            pat_data = json.load(pf)

        if pattern_id in pat_data.get("patterns", {}):
            pat_data["patterns"][pattern_id]["status"] = "routine_synthesized"
            pat_data["patterns"][pattern_id]["routineId"] = routine_id

        temp_file = mem_dir / f"patterns.json.tmp.{os.getpid()}"
        with open(temp_file, "w", encoding="utf-8") as tf:
            json.dump(pat_data, tf, indent=2)
            tf.flush()
            os.fsync(tf.fileno())
        os.replace(temp_file, patterns_file)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate Routine Maker receipts and check ready patterns.")
    parser.add_argument("--check", action="store_true", help="List patterns ready for routine synthesis")
    parser.add_argument("--receipt", type=str, help="Generate Receipt of Causality for a pattern ID")
    args = parser.parse_args()

    mem_dir = resolve_memory_dir()
    if args.check:
        ready = get_ready_patterns(mem_dir)
        print(f"Found {len(ready)} pattern(s) ready for Routine Maker synthesis:")
        for pat in ready:
            print(f"  - {pat['patternId']} (count: {pat['count']}, skill: {pat['targetSkill']})")
    elif args.receipt:
        ready = get_ready_patterns(mem_dir)
        matching = [p for p in ready if p["patternId"] == args.receipt]
        if not matching:
            print(f"Error: Pattern '{args.receipt}' not found or not ready.")
            sys.exit(1)
        lessons_map = load_lessons(mem_dir)
        receipt = generate_receipt_of_causality(matching[0], lessons_map)
        print(receipt)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
