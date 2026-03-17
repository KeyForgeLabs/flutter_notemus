import re

path = 'lib/src/parsers/musicxml_parser.dart'
with open(path, 'r') as f:
    text = f.read()

extract_logic = """
  static void _extractMarks(XmlElement measureElement, Measure measure) {
    for (final direction in measureElement.findAllElements('direction')) {
      final directionType = direction.getElement('direction-type');
      if (directionType == null) continue;

      for (final wordsElement in directionType.findAllElements('words')) {
        final text = wordsElement.text.trim().toLowerCase();
        if (text.contains('d.s. al coda')) {
          measure.navigationMarks = [...measure.navigationMarks, const RepeatMark(type: RepeatType.dalSegnoAlCoda)];
        } else if (text.contains('d.s. al fine')) {
          measure.navigationMarks = [...measure.navigationMarks, const RepeatMark(type: RepeatType.dalSegnoAlFine)];
        } else if (text.contains('d.c. al fine')) {
          measure.navigationMarks = [...measure.navigationMarks, const RepeatMark(type: RepeatType.daCapoAlFine)];
        } else if (text.contains('to coda')) {
          measure.navigationMarks = [...measure.navigationMarks, const RepeatMark(type: RepeatType.toCoda)];
        } else if (text.contains('fine')) {
          measure.navigationMarks = [...measure.navigationMarks, const RepeatMark(type: RepeatType.fine)];
        }
      }

      if (directionType.getElement('segno') != null) {
         measure.navigationMarks = [...measure.navigationMarks, const RepeatMark(type: RepeatType.segno)];
      }
      if (directionType.getElement('coda') != null) {
         measure.navigationMarks = [...measure.navigationMarks, const RepeatMark(type: RepeatType.coda)];
      }
    }

    for (final sound in measureElement.findAllElements('sound')) {
      if (sound.getAttribute('dacapo') == 'yes') {
        if (!measure.navigationMarks.any((m) => m.type == RepeatType.daCapo || m.type == RepeatType.daCapoAlFine)) {
          measure.navigationMarks = [...measure.navigationMarks, const RepeatMark(type: RepeatType.daCapo)];
        }
      }
      if (sound.getAttribute('dalsegno') != null) {
        if (!measure.navigationMarks.any((m) => m.type == RepeatType.dalSegno || m.type == RepeatType.dalSegnoAlCoda || m.type == RepeatType.dalSegnoAlFine)) {
          measure.navigationMarks = [...measure.navigationMarks, const RepeatMark(type: RepeatType.dalSegno)];
        }
      }
      if (sound.getAttribute('tocoda') != null) {
        if (!measure.navigationMarks.any((m) => m.type == RepeatType.toCoda)) {
          measure.navigationMarks = [...measure.navigationMarks, const RepeatMark(type: RepeatType.toCoda)];
        }
      }
      if (sound.getAttribute('fine') != null) {
        if (!measure.navigationMarks.any((m) => m.type == RepeatType.fine)) {
           measure.navigationMarks = [...measure.navigationMarks, const RepeatMark(type: RepeatType.fine)];
        }
      }
    }
  }
"""

if "_extractMarks(" not in text:
    last_brace = text.rfind('}')
    if last_brace != -1:
        text = text[:last_brace] + extract_logic + "\n}\n"
    
if "import '../core/repeat.dart';" not in text:
    text = text.replace("import '../core/score.dart';", "import '../core/score.dart';\nimport '../core/repeat.dart';")

text = text.replace(
    "return measure;", 
    "_extractMarks(measureElement, measure);\n    return measure;"
)

with open(path, 'w') as f:
    f.write(text)
