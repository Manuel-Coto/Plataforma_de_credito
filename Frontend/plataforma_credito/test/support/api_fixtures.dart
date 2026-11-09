import 'dart:convert';
import 'dart:io';

/// Estos JSON también se verifican contra las respuestas serializadas de Rust.
Map<String, dynamic> apiFixture(String name) => jsonDecode(
      File('test/fixtures/api/$name.json').readAsStringSync(),
    ) as Map<String, dynamic>;
