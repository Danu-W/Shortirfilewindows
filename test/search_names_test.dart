import 'package:flutter_test/flutter_test.dart';
import 'package:shortir_file/main.dart';
import 'package:shortir_file/search_names.dart';

void main() {
  const extensions = {'jpg', 'jpeg', 'png', 'pdf'};

  test('normalizeSearchName strips path, extension, punctuation', () {
    expect(normalizeSearchName('IMG_1234.JPG'), 'img1234');
    expect(normalizeSearchName('/Users/me/Photos/IMG_0001.png'), 'img0001');
    expect(normalizeSearchName('  "My Photo.jpg" '), 'myphoto');
  });

  test('detectFileNames splits lists but keeps plain names', () {
    expect(detectFileNames('IMG_1.jpg\nIMG_2.jpg', extensions: extensions), [
      'IMG_1.jpg',
      'IMG_2.jpg',
    ]);
    expect(detectFileNames('invoice', extensions: extensions), ['invoice']);
    expect(detectFileNames('1. IMG_1.jpg\n2. IMG_2.png', extensions: extensions), [
      'IMG_1.jpg',
      'IMG_2.png',
    ]);
    expect(detectFileNames('IMG_1.jpg IMG_2.jpg', extensions: extensions), [
      'IMG_1.jpg',
      'IMG_2.jpg',
    ]);
    expect(detectFileNames('cat dog bird', extensions: extensions), [
      'cat',
      'dog',
      'bird',
    ]);
    expect(detectFileNames('My Photo.jpg', extensions: extensions), [
      'My',
      'Photo.jpg',
    ]);
    expect(detectFileNames('"My Photo.jpg"', extensions: extensions), [
      'My Photo.jpg',
    ]);
  });

  test('mergeSearchNames appends, dedupes, ignores empty', () {
    expect(
      mergeSearchNames([], 'IMG_1.jpg', extensions),
      ['IMG_1.jpg'],
    );
    expect(
      mergeSearchNames(['IMG_1.jpg'], 'IMG_2.png', extensions),
      ['IMG_1.jpg', 'IMG_2.png'],
    );
    expect(
      mergeSearchNames(['IMG_1.jpg'], 'IMG_1.jpg', extensions),
      ['IMG_1.jpg'],
    );
    expect(mergeSearchNames(['a'], '   ', extensions), ['a']);
    expect(
      mergeSearchNames(['a'], 'b\nc', extensions),
      ['a', 'b', 'c'],
    );
  });
}
