#!/usr/bin/env python3
"""Outer Loop Evaluator for Grok Bot Agent Factory.

Inspects completed work-item runs and artifacts to extract structured Lesson
records against the four Quality Rubrics, recording them to the Memory Store.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

from scripts.memory_store import record_lesson, resolve_memory_dir


def evaluate_work_item(
    work_item: Dict[str, Any],
    *,
    audit_log: Optional[str] = None,
    diff_text: Optional[str] = None,
    mem_dir: Optional[Path] = None,
    threshold: int = 3,
) -> List[Dict[str, Any]]:
    """Evaluates a completed work-item against the Quality Rubrics and records lessons."""
    work_item_id = work_item.get("id", "unknown")
    target_skill = work_item.get("primarySkill") or work_item.get("builder", "poteto-mode")
    pr_url = work_item.get("prUrl")
    recorded_lessons = []

    # 1. Rubric: rework_frequency
    retry_count = work_item.get("retryCount", 0)
    if retry_count > 0:
        evidence = f"Work-item required {retry_count} rework retry attempts."
        if audit_log:
            evidence += f" Interrogation critique: {audit_log[:500]}"
        res = record_lesson(
            work_item_id=work_item_id,
            target_skill=target_skill,
            failure_class="audit_interrogation_failure",
            rubric_violated="rework_frequency",
            evidence_summary=evidence,
            pr_url=pr_url,
            threshold=threshold,
            mem_dir=mem_dir,
        )
        recorded_lessons.append(res)

    # 2. Rubric: reproduction_failure / blockers
    blockers = work_item.get("blockers", [])
    for blocker in blockers:
        if "reproduc" in blocker.lower() or "cannot reproduce" in blocker.lower():
            res = record_lesson(
                work_item_id=work_item_id,
                target_skill=target_skill,
                failure_class="reproduction_failure",
                rubric_violated="plan_then_build",
                evidence_summary=f"Reproduction blocker recorded: {blocker}",
                pr_url=pr_url,
                threshold=threshold,
                mem_dir=mem_dir,
            )
            recorded_lessons.append(res)

    # 3. Rubric: diff_economy
    if diff_text:
        lines = diff_text.strip().splitlines()
        added_lines = [l for l in lines if l.startswith("+") and not l.startswith("+++")]
        if len(added_lines) > 500:
            res = record_lesson(
                work_item_id=work_item_id,
                target_skill=target_skill,
                failure_class="excessive_churn",
                rubric_violated="diff_economy",
                evidence_summary=f"Diff exceeded economy threshold: {len(added_lines)} added lines.",
                pr_url=pr_url,
                threshold=threshold,
                mem_dir=mem_dir,
            )
            recorded_lessons.append(res)

    return recorded_lessons


def evaluate_work_item_file(
    file_path: Path,
    mem_dir: Optional[Path] = None,
    threshold: int = 3,
) -> List[Dict[str, Any]]:
    """Loads a work-item JSON file and evaluates it."""
    with open(file_path, "r", encoding="utf-8") as f:
        work_item = json.load(f)

    work_item_id = work_item.get("id", file_path.stem)
    audit_path = file_path.parent.parent / "artifacts" / work_item_id / "audit.log"
    audit_log = None
    if audit_path.exists():
        with open(audit_path, "r", encoding="utf-8") as af:
            audit_log = af.read()

    return evaluate_work_item(
        work_item,
        audit_log=audit_log,
        mem_dir=mem_dir,
        threshold=threshold,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Evaluate factory run artifacts and record lessons.")
    parser.add_argument("--work-item", type=str, help="Path to work-item JSON file")
    parser.add_argument("--threshold", type=int, default=3, help="Repetition threshold")
    args = parser.parse_args()

    if args.work_item:
        results = evaluate_work_item_file(Path(args.work_item), threshold=args.threshold)
        print(f"Recorded {len(results)} lesson(s) for {args.work_item}")
    else:
        print("Usage: evaluator.py --work-item <path-to-work-item.json>")
        sys.exit(1)


if __name__ == "__main__":
    main()
