import json
import shutil
import tempfile
import unittest
from pathlib import Path

from scripts.memory_store import record_lesson
from scripts.routine_maker import (
    generate_receipt_of_causality,
    load_lessons,
    mark_pattern_synthesized,
)


class TestRoutineMaker(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp(prefix="test_routine_maker_")
        self.mem_dir = Path(self.test_dir) / ".factory" / "memory"
        self.mem_dir.mkdir(parents=True, exist_ok=True)

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_generate_receipt_of_causality(self):
        # Accumulate 3 lessons to trigger threshold
        for i in range(3):
            record_lesson(
                work_item_id=f"gh-issue-{i}",
                target_skill="poteto-mode",
                failure_class="audit_interrogation_failure",
                rubric_violated="principle-fix-root-causes",
                evidence_summary=f"Audit failed in test run {i}",
                threshold=3,
                mem_dir=self.mem_dir,
            )

        patterns_file = self.mem_dir / "patterns.json"
        with open(patterns_file, "r", encoding="utf-8") as f:
            pat_data = json.load(f)

        pattern = pat_data["patterns"]["audit_interrogation_failure::poteto-mode"]
        self.assertTrue(pattern["readyForRoutineMaker"])

        lessons_map = load_lessons(self.mem_dir)
        receipt = generate_receipt_of_causality(pattern, lessons_map)

        self.assertIn("## Receipt of Causality", receipt)
        self.assertIn("- **Target Skill**: `poteto-mode`", receipt)
        self.assertIn("- **Failure Class**: `audit_interrogation_failure`", receipt)
        self.assertIn("- **Repetition Count**: `3`", receipt)
        self.assertIn("gh-issue-0", receipt)
        self.assertIn("ADR 0001", receipt)

    def test_mark_pattern_synthesized(self):
        res = record_lesson(
            work_item_id="gh-issue-1",
            target_skill="poteto-mode",
            failure_class="audit_interrogation_failure",
            rubric_violated="principle-fix-root-causes",
            evidence_summary="Audit failed",
            threshold=1,
            mem_dir=self.mem_dir,
        )
        pattern_id = res["pattern"]["patternId"]
        mark_pattern_synthesized(self.mem_dir, pattern_id, routine_id="PR-45")

        patterns_file = self.mem_dir / "patterns.json"
        with open(patterns_file, "r", encoding="utf-8") as f:
            pat_data = json.load(f)

        entry = pat_data["patterns"][pattern_id]
        self.assertEqual(entry["status"], "routine_synthesized")
        self.assertEqual(entry["routineId"], "PR-45")


if __name__ == "__main__":
    unittest.main()
