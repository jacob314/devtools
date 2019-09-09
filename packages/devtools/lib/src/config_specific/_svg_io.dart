library svg;

import '_html_common_io.dart';

@Unstable()
@Native("SVGMatrix")
class Matrix extends Interceptor {
  // To suppress missing implicit constructor warnings.
  factory Matrix._() {
    throw new UnsupportedError("Not supported");
  }

  num a;

  num b;

  num c;

  num d;

  num e;

  num f;

  Matrix flipX() => unsupported();

  Matrix flipY() => unsupported();

  Matrix inverse() => unsupported();

  Matrix multiply(Matrix secondMatrix) => unsupported();

  Matrix rotate(num angle) => unsupported();

  Matrix rotateFromVector(num x, num y) => unsupported();

  Matrix scale(num scaleFactor) => unsupported();

  Matrix scaleNonUniform(num scaleFactorX, num scaleFactorY) => unsupported();

  Matrix skewX(num angle) => unsupported();

  Matrix skewY(num angle) => unsupported();

  Matrix translate(num x, num y) => unsupported();
}