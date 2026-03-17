import 'package:flutter_notemus/core/measure.dart';
import 'package:flutter_notemus/core/repeat.dart';
import 'package:flutter_notemus/src/parsers/musicxml_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MusicXMLParser Navigation Marks Parsing', () {
    test('Parses Segno direction correctly', () {
      const xmlString = '''
        <score-partwise>
          <part>
            <measure>
              <direction>
                <direction-type>
                  <segno/>
                </direction-type>
              </direction>
            </measure>
          </part>
        </score-partwise>
      ''';

      final staff = MusicXMLParser.parseMusicXML(xmlString);
      final measure = staff.measures.first;
      expect(measure.navigationMarks.length, 1);
      expect(measure.navigationMarks.first.type, RepeatType.segno);
    });

    test('Parses D.S. al Coda from words', () {
      const xmlString = '''
        <score-partwise>
          <part>
            <measure>
              <direction>
                <direction-type>
                  <words>D.S. al Coda</words>
                </direction-type>
                <sound dalsegno="segno"/>
              </direction>
            </measure>
          </part>
        </score-partwise>
      ''';

      final staff = MusicXMLParser.parseMusicXML(xmlString);
      final measure = staff.measures.first;
      // Depending on your fallback logic, this may parse both a `dalSegnoAlCoda` and a `dalSegno`
      // or just one. The parser script adds `dalSegno` if not already present.
      expect(measure.navigationMarks.isNotEmpty, isTrue);
      // Let's just check the first one
      expect(measure.navigationMarks.any((m) => m.type == RepeatType.dalSegnoAlCoda), isTrue);
    });

    test('Parses Da Capo from sound attribute', () {
      const xmlString = '''
        <score-partwise>
          <part>
            <measure>
              <direction>
                <sound dacapo="yes"/>
              </direction>
            </measure>
          </part>
        </score-partwise>
      ''';

      final staff = MusicXMLParser.parseMusicXML(xmlString);
      final measure = staff.measures.first;
      expect(measure.navigationMarks.length, 1);
      expect(measure.navigationMarks.first.type, RepeatType.daCapo);
    });
  });
}
