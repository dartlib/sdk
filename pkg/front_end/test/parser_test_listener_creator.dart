// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:typed_data';

import 'package:_fe_analyzer_shared/src/parser/parser.dart';
import 'package:_fe_analyzer_shared/src/parser/formal_parameter_kind.dart';
import 'package:_fe_analyzer_shared/src/parser/listener.dart';
import 'package:_fe_analyzer_shared/src/parser/member_kind.dart';
import 'package:_fe_analyzer_shared/src/scanner/utf8_bytes_scanner.dart';
import 'package:_fe_analyzer_shared/src/scanner/token.dart';
import 'package:dart_style/dart_style.dart' show DartFormatter;

StringSink out;

const Set<String> specialHandledMethods = {
  "beginBinaryExpression",
  "endBinaryExpression",
};

main(List<String> args) {
  if (args.contains("--stdout")) {
    out = stdout;
  } else {
    out = new StringBuffer();
  }

  File f = new File.fromUri(Platform.script
      .resolve("../../_fe_analyzer_shared/lib/src/parser/listener.dart"));
  List<int> rawBytes = f.readAsBytesSync();

  Uint8List bytes = new Uint8List(rawBytes.length + 1);
  bytes.setRange(0, rawBytes.length, rawBytes);

  Utf8BytesScanner scanner = new Utf8BytesScanner(bytes, includeComments: true);
  Token firstToken = scanner.tokenize();

  out.write(r"""
// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:_fe_analyzer_shared/src/parser/assert.dart';
import 'package:_fe_analyzer_shared/src/parser/block_kind.dart';
import 'package:_fe_analyzer_shared/src/parser/declaration_kind.dart';
import 'package:_fe_analyzer_shared/src/parser/formal_parameter_kind.dart';
import 'package:_fe_analyzer_shared/src/parser/identifier_context.dart';
import 'package:_fe_analyzer_shared/src/parser/listener.dart';
import 'package:_fe_analyzer_shared/src/parser/member_kind.dart';
import 'package:_fe_analyzer_shared/src/scanner/error_token.dart';
import 'package:_fe_analyzer_shared/src/scanner/token.dart';
import 'package:front_end/src/fasta/messages.dart';

// THIS FILE IS AUTO GENERATED BY 'test/parser_test_listener_creator.dart'
// Run e.g.
/*
   out/ReleaseX64/dart \
     pkg/front_end/test/parser_test_listener_creator.dart \
      > pkg/front_end/test/parser_test_listener.dart
*/

class ParserTestListener implements Listener {
  int indent = 0;
  final StringBuffer sb = new StringBuffer();
  final bool trace;

  ParserTestListener(this.trace);

  String createTrace() {
    List<String> traceLines = StackTrace.current.toString().split("\n");
    for (int i = 0; i < traceLines.length; i++) {
      // Find first one that's not any of the blacklisted ones.
      String line = traceLines[i];
      if (line.contains("parser_test_listener.dart:") ||
          line.contains("parser_suite.dart:")) continue;
      return line.substring(line.indexOf("(") + 1, line.lastIndexOf(")"));
    }
    return "N/A";
  }

  void doPrint(String s) {
    String outString = s;
    if (trace) outString += " (${createTrace()})";
    if (outString != "") {
      sb.writeln(("  " * indent) + outString);
    } else {
      sb.writeln("");
    }
  }

  void seen(Token token) {}

""");

  ParserCreatorListener listener = new ParserCreatorListener();
  ClassMemberParser parser = new ClassMemberParser(listener);
  parser.parseUnit(firstToken);

  out.writeln("}");

  if (out is StringBuffer) {
    String text = new DartFormatter().format("$out");
    if (args.isNotEmpty) {
      new File(args.first).writeAsStringSync(text);
    } else {
      stdout.write(text);
    }
  }
}

class ParserCreatorListener extends Listener {
  bool insideListenerClass = false;
  String currentMethodName;
  String latestSeenParameterTypeToken;
  List<String> parameters = <String>[];
  List<String> parameterTypes = <String>[];

  void beginClassDeclaration(Token begin, Token abstractToken, Token name) {
    if (name.lexeme == "Listener") insideListenerClass = true;
  }

  void endClassDeclaration(Token beginToken, Token endToken) {
    insideListenerClass = false;
  }

  void beginMethod(Token externalToken, Token staticToken, Token covariantToken,
      Token varFinalOrConst, Token getOrSet, Token name) {
    currentMethodName = name.lexeme;
  }

  void endClassMethod(Token getOrSet, Token beginToken, Token beginParam,
      Token beginInitializers, Token endToken) {
    if (insideListenerClass) {
      out.write("  ");
      Token token = beginToken;
      Token latestToken;
      while (true) {
        if (latestToken != null && latestToken.charEnd < token.charOffset) {
          out.write(" ");
        }
        out.write(token.lexeme);
        if ((token is BeginToken &&
                token.type == TokenType.OPEN_CURLY_BRACKET) ||
            token is SimpleToken && token.type == TokenType.FUNCTION) {
          break;
        }
        if (token == endToken) {
          throw token.runtimeType;
        }
        latestToken = token;
        token = token.next;
      }

      if (token is SimpleToken && token.type == TokenType.FUNCTION) {
        out.write(" null;");
      } else {
        out.write("\n    ");
        if (!specialHandledMethods.contains(currentMethodName) &&
            currentMethodName.startsWith("end")) {
          out.write("indent--;\n    ");
        }
        for (int i = 0; i < parameterTypes.length; i++) {
          if (parameterTypes[i] == "Token") {
            out.write("seen(${parameters[i]});");
          }
        }
        out.write("doPrint('$currentMethodName(");
        String separator = "";
        for (int i = 0; i < parameters.length; i++) {
          out.write(separator);
          out.write(r"' '$");
          out.write(parameters[i]);
          separator = ", ";
        }
        out.write(")');\n  ");

        if (!specialHandledMethods.contains(currentMethodName) &&
            currentMethodName.startsWith("begin")) {
          out.write("  indent++;\n  ");
        }

        out.write("}");
      }
      out.write("\n\n");
    }
    parameters.clear();
    parameterTypes.clear();
    currentMethodName = null;
  }

  @override
  void handleNoType(Token lastConsumed) {
    latestSeenParameterTypeToken = null;
  }

  void handleType(Token beginToken, Token questionMark) {
    latestSeenParameterTypeToken = beginToken.lexeme;
  }

  void endFormalParameter(
      Token thisKeyword,
      Token periodAfterThis,
      Token nameToken,
      Token initializerStart,
      Token initializerEnd,
      FormalParameterKind kind,
      MemberKind memberKind) {
    parameters.add(nameToken.lexeme);
    parameterTypes.add(latestSeenParameterTypeToken);
  }
}
