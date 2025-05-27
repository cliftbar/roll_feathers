/*
https://github.com/flutter/website/commit/c6034e667d41666ee40b5917291471a9b3db2f05

Except as otherwise noted, the content of this repository is licensed under the
Creative Commons Attribution 3.0 License [1], and code samples are licensed
under the BSD License:

Copyright 2012, the project authors. All rights reserved. Redistribution and use
in source and binary forms, with or without modification, are permitted provided
that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google Inc. nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

[1] http://creativecommons.org/licenses/by/3.0/
 */

// Copyright 2024 The Flutter team. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';
import 'package:flutter/foundation.dart';

typedef CommandAction0<T> = Future<Result<T>> Function();
typedef CommandAction1<T, A> = Future<Result<T>> Function(A);
typedef CommandAction2<T, A, B> = Future<Result<T>> Function(A, B);
typedef CommandAction3<T, A, B, C> = Future<Result<T>> Function(A, B, C);
typedef CommandAction4<T, A, B, C, D> = Future<Result<T>> Function(A, B, C, D);

/// Facilitates interaction with a ViewModel.
///
/// Encapsulates an action,
/// exposes its running and error states,
/// and ensures that it can't be launched again until it finishes.
///
/// Use [Command0] for actions without arguments.
/// Use [Command1] for actions with one argument.
///
/// Actions must return a [Result].
///
/// Consume the action result by listening to changes,
/// then call to [clearResult] when the state is consumed.
abstract class Command<T> extends ChangeNotifier {
  Command();

  bool _running = false;

  /// True when the action is running.
  bool get running => _running;

  Result<T>? _result;

  /// true if action completed with error
  bool get error => _result?.isError ?? true;

  /// true if action completed successfully
  bool get completed => _result?.isValue ?? false;

  /// Get last action result
  Result? get result => _result;

  /// Clear last action result
  void clearResult() {
    _result = null;
    notifyListeners();
  }

  /// Internal execute implementation
  Future<void> _execute(CommandAction0<T> action) async {
    // Ensure the action can't launch multiple times.
    // e.g. avoid multiple taps on button
    if (_running) return;

    // Notify listeners.
    // e.g. button shows loading state
    _running = true;
    _result = null;
    notifyListeners();

    try {
      _result = await action();
    } finally {
      _running = false;
      notifyListeners();
    }
  }
}

/// [Command] without arguments.
/// Takes a [CommandAction0] as action.
class Command0<T> extends Command<T> {
  Command0(this._action);

  final CommandAction0<T> _action;

  /// Executes the action.
  Future<void> execute() async {
    await _execute(() => _action());
  }
}

/// [Command] with one argument.
/// Takes a [CommandAction1] as action.
class Command1<T, A> extends Command<T> {
  Command1(this._action);

  final CommandAction1<T, A> _action;

  /// Executes the action with the argument.
  Future<void> execute(A argument) async {
    await _execute(() => _action(argument));
  }
}

/// [Command] with two arguments.
/// Takes a [CommandAction2] as action.
class Command2<T, A, B> extends Command<T> {
  Command2(this._action);

  final CommandAction2<T, A, B> _action;

  /// Executes the action with the argument.
  Future<void> execute(A arg1, B arg2) async {
    await _execute(() => _action(arg1, arg2));
  }
}

class Command3<T, A, B, C> extends Command<T> {
  Command3(this._action);

  final CommandAction3<T, A, B, C> _action;

  /// Executes the action with the argument.
  Future<void> execute(A arg1, B arg2, C arg3) async {
    await _execute(() => _action(arg1, arg2, arg3));
  }
}

/// [Command] with four arguments.
/// Takes a [CommandAction4] as action.
class Command4<T, A, B, C, D> extends Command<T> {
  Command4(this._action);

  final CommandAction4<T, A, B, C, D> _action;

  /// Executes the action with the argument.
  Future<void> execute(A arg1, B arg2, C arg3, D arg4) async {
    await _execute(() => _action(arg1, arg2, arg3, arg4));
  }
}
