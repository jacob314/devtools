library html;

export '_html_io.dart'
    if (dart.library.html) 'package:devtools/src/config_specific/html.dart';

bool get isHtmlSupported {
    double oneDouble = 1.0;
    int oneInt = 1;
    // TODO(jacobr): use actual config specific imports instead of checking if
    // this is JavaScript or not.
    return !identical(oneDouble, oneInt);
}