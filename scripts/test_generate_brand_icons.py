#!/usr/bin/env python3

import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "scripts" / "generate_brand_icons.py"
GENERATED_BRAND_PATHS = [
    "Assets/Brand/AppIcon.appiconset",
    "Assets/Brand/OpenIsland.iconset",
    "Assets/Brand/Internal",
    "Assets/Brand/OpenIsland.icns",
    "Assets/Brand/scout-app-icon-master.svg",
]


class GenerateBrandIconsTests(unittest.TestCase):
    def test_temp_icns_output_leaves_tracked_brand_assets_untouched(self) -> None:
        before = subprocess.run(
            ["git", "diff", "--quiet", "--", *GENERATED_BRAND_PATHS],
            cwd=REPO_ROOT,
            check=False,
        )
        self.assertEqual(before.returncode, 0, "generated brand assets must start clean for this test")

        with tempfile.TemporaryDirectory() as temp_dir:
            output_root = Path(temp_dir) / "brand"
            result = subprocess.run(
                [
                    "python3",
                    str(SCRIPT_PATH),
                    "--output-root",
                    str(output_root),
                    "--icns-only",
                ],
                cwd=REPO_ROOT,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((output_root / "OpenIsland.icns").is_file())
            self.assertTrue((output_root / "OpenIsland.iconset").is_dir())

        after = subprocess.run(
            ["git", "diff", "--quiet", "--", *GENERATED_BRAND_PATHS],
            cwd=REPO_ROOT,
            check=False,
        )
        self.assertEqual(after.returncode, 0, "temporary icns generation must not dirty tracked brand outputs")


if __name__ == "__main__":
    unittest.main()
