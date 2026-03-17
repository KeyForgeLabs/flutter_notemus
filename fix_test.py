with open("test/parsers/musicxml_navigation_test.dart", "r") as f:
    text = f.read()

text = text.replace("MusicXMLParser.parseString(xmlString);", "MusicXMLParser.parseMusicXML(xmlString);")
text = text.replace("final score = ", "final staff = ")
text = text.replace("score.parts.first.measures.first", "staff.measures.first")

with open("test/parsers/musicxml_navigation_test.dart", "w") as f:
    f.write(text)
