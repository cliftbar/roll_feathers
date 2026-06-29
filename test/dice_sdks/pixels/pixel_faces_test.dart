import 'package:flutter_test/flutter_test.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixel_faces.dart';
import 'package:roll_feathers/dice_sdks/pixels/pixels.dart';

void main() {
  group('faceCount / dieFaces', () {
    test('per die type', () {
      expect(PixelFaces.faceCount(PixelDieType.d4), 4);
      expect(PixelFaces.faceCount(PixelDieType.d6), 6);
      expect(PixelFaces.faceCount(PixelDieType.d8), 8);
      expect(PixelFaces.faceCount(PixelDieType.d10), 10);
      expect(PixelFaces.faceCount(PixelDieType.d00), 10);
      expect(PixelFaces.faceCount(PixelDieType.d12), 12);
      expect(PixelFaces.faceCount(PixelDieType.d20), 20);
      expect(PixelFaces.faceCount(PixelDieType.d6Pipped), 6);
      expect(PixelFaces.faceCount(PixelDieType.d6Fudge), 6);
    });

    test('dieFaces lists', () {
      expect(PixelFaces.dieFaces(PixelDieType.d4), [1, 2, 3, 4]);
      expect(PixelFaces.dieFaces(PixelDieType.d6), [1, 2, 3, 4, 5, 6]);
      expect(PixelFaces.dieFaces(PixelDieType.d10), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
      expect(PixelFaces.dieFaces(PixelDieType.d00), [0, 10, 20, 30, 40, 50, 60, 70, 80, 90]);
      expect(PixelFaces.dieFaces(PixelDieType.d20), [for (var f = 1; f <= 20; f++) f]);
    });

    test('highest / lowest face', () {
      expect(PixelFaces.highestFace(PixelDieType.d20), 20);
      expect(PixelFaces.highestFace(PixelDieType.d4), 4);
      expect(PixelFaces.highestFace(PixelDieType.d10), 0);
      expect(PixelFaces.highestFace(PixelDieType.d00), 0);
      expect(PixelFaces.lowestFace(PixelDieType.d20), 1);
      expect(PixelFaces.lowestFace(PixelDieType.d00), 10);
    });
  });

  group('indexFromFace / faceFromIndex (current firmware)', () {
    test('default dice are face-1 / index+1', () {
      expect(PixelFaces.indexFromFace(20, PixelDieType.d20), 19);
      expect(PixelFaces.faceFromIndex(19, PixelDieType.d20), 20);
      expect(PixelFaces.indexFromFace(4, PixelDieType.d4), 3);
      expect(PixelFaces.faceFromIndex(3, PixelDieType.d4), 4);
    });

    test('d10 is identity (0-9)', () {
      expect(PixelFaces.indexFromFace(5, PixelDieType.d10), 5);
      expect(PixelFaces.faceFromIndex(5, PixelDieType.d10), 5);
      expect(PixelFaces.faceFromIndex(0, PixelDieType.d10), 0);
      expect(PixelFaces.faceFromIndex(9, PixelDieType.d10), 9);
    });

    test('d00 maps tens (0/10/.../90)', () {
      expect(PixelFaces.indexFromFace(50, PixelDieType.d00), 5);
      expect(PixelFaces.faceFromIndex(5, PixelDieType.d00), 50);
      expect(PixelFaces.faceFromIndex(0, PixelDieType.d00), 0);
      expect(PixelFaces.faceFromIndex(9, PixelDieType.d00), 90);
    });
  });

  group('faceMask', () {
    test('d20 selections match the legacy hardcoded constants', () {
      expect(PixelFaces.faceMask(PixelFaces.dieFaces(PixelDieType.d20), PixelDieType.d20), 0xFFFFF);
      expect(PixelFaces.faceMask([for (var f = 11; f <= 20; f++) f], PixelDieType.d20), 0xFFC00);
      expect(PixelFaces.faceMask([20], PixelDieType.d20), 0x80000);
      expect(PixelFaces.faceMask([1], PixelDieType.d20), 0x1);
    });

    test('other dice all-faces masks', () {
      expect(PixelFaces.faceMask(PixelFaces.dieFaces(PixelDieType.d4), PixelDieType.d4), 0xF);
      expect(PixelFaces.faceMask(PixelFaces.dieFaces(PixelDieType.d6), PixelDieType.d6), 0x3F);
      expect(PixelFaces.faceMask(PixelFaces.dieFaces(PixelDieType.d10), PixelDieType.d10), 0x3FF);
      // d00 indices are 0-9 too → same mask as d10.
      expect(PixelFaces.faceMask(PixelFaces.dieFaces(PixelDieType.d00), PixelDieType.d00), 0x3FF);
    });
  });
}
