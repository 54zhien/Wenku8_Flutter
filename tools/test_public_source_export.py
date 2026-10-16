import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("export_source", Path(__file__).with_name("export_public_source.py"))
export_source = importlib.util.module_from_spec(spec)
spec.loader.exec_module(export_source)


class PublicSourceExportTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name).resolve()
        self.root = self.base / "project"
        for name in ("lib/main.dart", "android/local.properties", "android/key.properties",
                     "android/gradle/wrapper/gradle-wrapper.jar", "android/.gradle/cache.bin",
                     "android/app/src/main/jniLibs/arm64-v8a/libcpp.so",
                     "ios/Runner.xcodeproj/xcuserdata/private.xcuserstate",
                     "lib/performance_page.dart", "lib/render_budget_probe.dart",
                     "third_party/liquid_glass_easy/pubspec.yaml",
                     "third_party/liquid_glass_easy/LICENSE",
                     "third_party/liquid_glass_easy/lib/liquid_glass_easy.dart",
                     "flutter_screenshots/private.png", "LISTENING.md", "README.md"):
            file = self.root / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text("fixture")

    def export(self, output, *args):
        with patch.object(export_source, "ROOT", self.root), \
                patch("sys.argv", ["export_public_source.py", str(output), *args]), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            export_source.main()

    def test_complete_candidate_keeps_the_embedded_dependency_without_local_data(self):
        output = self.base / "complete"
        self.export(output)
        files = {p.relative_to(output).as_posix() for p in output.rglob("*") if p.is_file()}
        self.assertEqual(files, {"README.md", "lib/main.dart",
            "third_party/liquid_glass_easy/pubspec.yaml",
            "third_party/liquid_glass_easy/LICENSE",
            "third_party/liquid_glass_easy/lib/liquid_glass_easy.dart",
            "android/gradle/wrapper/gradle-wrapper.jar",
            "android/app/src/main/jniLibs/arm64-v8a/libcpp.so"})

    def test_source_only_is_explicit_and_leaves_runtime_out(self):
        output = self.base / "source-only"
        self.export(output, "--source-only")
        self.assertFalse(any(output.rglob("libcpp.so")))

    def test_ios_export_keeps_build_workflow_codec_generator_and_instructions(self):
        required = ("native_tests/GenerateGBKMap.java", "native_tests/WenkuProtocolTests.swift",
                    ".github/workflows/ios.yml", "docs/IOS.md", "ios/Runner/Resources/gbk-map.bin",
                    "tools/ci_boot_ios_simulator.py", "tools/test_ci_boot_ios_simulator.py",
                    "tools/select_ios_simulators.py", "tools/test_select_ios_simulators.py",
                    ".github/workflows/ios-diagnostic.yml", "tools/verify_ios_archive.py", "tools/test_verify_ios_archive.py")
        for name in required:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("ios fixture")
        output = self.base / "ios"
        self.export(output)
        for name in required:
            self.assertTrue((output / name).is_file(), name)

    def test_never_overwrites_an_existing_export(self):
        output = self.base / "existing"
        output.mkdir()
        marker = output / "keep.txt"
        marker.write_text("keep")
        with self.assertRaises(SystemExit):
            self.export(output)
        self.assertEqual(marker.read_text(), "keep")

    def test_never_exports_recursively_into_the_source_tree(self):
        with self.assertRaises(SystemExit):
            self.export(self.root / "lib" / "output")


if __name__ == "__main__":
    unittest.main()
