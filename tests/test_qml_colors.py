"""The plugin's QML reaches Omarchy's colors through `Commons.Color`.

Run with: python3 -m unittest discover -s tests

Qt 6.12 adds a `Color` singleton to QtQuick, and it shadows the `Color` that
`import qs.Commons` provides. A bare `Color.accent` then reads undefined: on
Omarchy 4.5 the appearance panel's toggles were handed no accent that way,
with a warning for each, and the capture host drew an empty bar. Omarchy's own
QML imports `qs.Commons as Commons` and writes `Commons.Color`, and so does
this plugin.
"""

import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BARE_COLOR = re.compile(r"(?<![\w.])Color\.")


def qml_files():
    for directory, subdirectories, names in os.walk(ROOT):
        subdirectories[:] = [name for name in subdirectories if not name.startswith(".")]
        for name in names:
            if name.endswith(".qml"): yield os.path.join(directory, name)


class QmlColorTest(unittest.TestCase):
    def test_no_bare_color_singleton(self):
        paths = list(qml_files())
        self.assertIn(os.path.join(ROOT, "BarWidget.qml"), paths)
        for path in paths:
            with open(path, encoding="utf-8") as source:
                text = source.read()
            relative = os.path.relpath(path, ROOT)
            for number, line in enumerate(text.splitlines(), 1):
                code = line.split("//", 1)[0]
                self.assertIsNone(BARE_COLOR.search(code), f"{relative}:{number}: {line.strip()}")
            if "Commons.Color" in text:
                self.assertIn("import qs.Commons as Commons", text, relative)

    def test_catches_a_bare_reference(self):
        self.assertIsNotNone(BARE_COLOR.search("accent: Color.accent"))
        self.assertIsNone(BARE_COLOR.search("accent: Commons.Color.accent"))
        self.assertIsNone(BARE_COLOR.search("property color barColor: theme.Color"))


if __name__ == "__main__": unittest.main()
