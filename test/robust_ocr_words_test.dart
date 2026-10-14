import 'package:flutter_test/flutter_test.dart';
import 'package:kistbook/services/parsers.dart';

OcrWord w(String t, double left, double right, double top) =>
    OcrWord(t, left: left, right: right, top: top);

void main() {
  test('dedupe: tile overlap ke dohre words ek ho jate hain', () {
    // Do tiles ne overlap me "7150" do baar parha (zara si position farq).
    final words = [
      w('003112', 10, 60, 100),
      w('7150', 300, 340, 100),
      w('7150', 303, 343, 101),
      w('Razaq', 100, 150, 100),
    ];
    final out = dedupeOcrWords(words);
    expect(out.length, 3);
    expect(out.where((e) => e.text == '7150').length, 1);
  });

  test('dedupe: mukammal wala rehta hai, adhoora jata hai', () {
    final words = [w('410', 300, 330, 100), w('4100', 300, 345, 100)];
    final out = dedupeOcrWords(words);
    expect(out.length, 1);
    expect(out.single.text, '4100');
  });

  test('dedupe: mukhtalif jagah ke same words NAHI kat te', () {
    // Do mukhtalif customers ka due ittefaqan same — dono rehne chahiye.
    final words = [w('5000', 300, 340, 100), w('5000', 300, 340, 160)];
    final out = dedupeOcrWords(words);
    expect(out.length, 2);
  });

  test('grouping: offset wale tile words ek line me judte hain', () {
    // Neeche wale tile ke words (top offset 1200 ke sath) apni rows banate
    // hain; upar wale apni. Har line left-to-right sorted hoti hai.
    final words = [
      w('B', 100, 130, 1300),
      w('A', 10, 60, 1300),
      w('X', 10, 60, 100),
      w('Y', 100, 130, 102),
    ];
    final lines = groupWordsIntoLines(words);
    expect(lines.length, 2);
    expect(lines[0].text, 'X Y');
    expect(lines[1].text, 'A B');
  });
}
