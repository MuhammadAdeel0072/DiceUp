/// Test-only failure injection for SQLite transaction tests (M1.4).
///
/// A [Database] wrapper that delegates every call to the real
/// database but throws [error] on the Nth write while armed — so a
/// test can make `recordMatch` (or any multi-step operation) fail at
/// a chosen step inside its transaction and prove the whole
/// transaction rolled back. The wrapper is never used by production
/// code; it exists only so tests do not have to corrupt a real
/// database to observe a mid-transaction failure.
///
/// Writes counted: [insert], [rawInsert], [update], [rawUpdate],
/// [delete], [rawDelete] — the six write calls the repositories
/// use. Reads and [execute]/[batch] are never counted and never
/// fail. The plan only counts while armed: set up state with the
/// wrapper disarmed, arm it immediately before the call under test,
/// and disarm it before verifying the aftermath (verification reads
/// the inner database directly).
///
/// The failure is thrown BEFORE the write is executed, so the
/// failing step itself leaves nothing behind; sqflite rolls back
/// the enclosing transaction and rethrows the error to the caller.
library;

import 'package:sqflite/sqflite.dart';

/// One-shot failure plan shared by a [FailingDatabase] and the
/// [FailingTransaction]s it creates, so writes are counted across
/// the whole transaction (outer calls + calls on the transaction
/// object share one counter).
class FailurePlan {
  /// Arms the plan: the [writeIndex]th write (1-based) throws
  /// [error]. A [writeIndex] of 0 disarms.
  void arm(int writeIndex, [Object? error]) {
    _failOnWrite = writeIndex;
    _error = error ?? const SimulatedRepositoryFailure();
    _writesSeen = 0;
  }

  /// Disarms the plan and resets the counter.
  void disarm() {
    _failOnWrite = 0;
    _writesSeen = 0;
  }

  /// Whether a failure is currently armed.
  bool get armed => _failOnWrite > 0;

  int _failOnWrite = 0;
  int _writesSeen = 0;
  Object _error = const SimulatedRepositoryFailure();

  /// Called before each counted write. Throws the armed error when
  /// this is the write the plan targets.
  void beforeWrite() {
    if (!armed) return;
    _writesSeen++;
    if (_writesSeen == _failOnWrite) {
      final error = _error;
      disarm();
      throw error;
    }
  }
}

/// The default injected error. A distinct public type so tests can assert
/// the injected failure (and not some other error) propagated.
class SimulatedRepositoryFailure implements Exception {
  const SimulatedRepositoryFailure([
    this.message = 'Simulated repository failure.',
  ]);

  final String message;

  @override
  String toString() => 'SimulatedRepositoryFailure: $message';
}

/// A [DatabaseExecutor] that delegates to [_inner] and fails the
/// armed write (see [FailurePlan]).
class FailingDatabaseExecutor implements DatabaseExecutor {
  FailingDatabaseExecutor(this._inner, this._plan);

  final DatabaseExecutor _inner;
  final FailurePlan _plan;

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) =>
      _inner.execute(sql, arguments);

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) {
    _plan.beforeWrite();
    return _inner.rawInsert(sql, arguments);
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) {
    _plan.beforeWrite();
    return _inner.insert(
      table,
      values,
      nullColumnHack: nullColumnHack,
      conflictAlgorithm: conflictAlgorithm,
    );
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => _inner.query(
    table,
    distinct: distinct,
    columns: columns,
    where: where,
    whereArgs: whereArgs,
    groupBy: groupBy,
    having: having,
    orderBy: orderBy,
    limit: limit,
    offset: offset,
  );

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) => _inner.rawQuery(sql, arguments);

  @override
  Future<QueryCursor> rawQueryCursor(
    String sql,
    List<Object?>? arguments, {
    int? bufferSize,
  }) => _inner.rawQueryCursor(sql, arguments, bufferSize: bufferSize);

  @override
  Future<QueryCursor> queryCursor(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
    int? bufferSize,
  }) => _inner.queryCursor(
    table,
    distinct: distinct,
    columns: columns,
    where: where,
    whereArgs: whereArgs,
    groupBy: groupBy,
    having: having,
    orderBy: orderBy,
    limit: limit,
    offset: offset,
    bufferSize: bufferSize,
  );

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) {
    _plan.beforeWrite();
    return _inner.rawUpdate(sql, arguments);
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) {
    _plan.beforeWrite();
    return _inner.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
      conflictAlgorithm: conflictAlgorithm,
    );
  }

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) {
    _plan.beforeWrite();
    return _inner.rawDelete(sql, arguments);
  }

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) {
    _plan.beforeWrite();
    return _inner.delete(table, where: where, whereArgs: whereArgs);
  }

  @override
  Batch batch() => _inner.batch();

  @override
  Database get database => _inner.database;
}

/// A [Transaction] that delegates to the real transaction and fails
/// the armed write (see [FailurePlan]). `Transaction` adds no
/// members to [DatabaseExecutor], so this is just the executor
/// wrapper under the transaction type.
class FailingTransaction extends FailingDatabaseExecutor
    implements Transaction {
  FailingTransaction(super.inner, super.plan);
}

/// A [Database] that delegates to [_innerDb] and fails the armed
/// write (see [FailurePlan]). Transactions created through it hand
/// the callback a [FailingTransaction] wrapping the real
/// transaction, so the plan counts writes across the whole
/// transaction.
class FailingDatabase extends FailingDatabaseExecutor implements Database {
  FailingDatabase(Database super._inner, super._plan) : _innerDb = _inner;

  final Database _innerDb;

  @override
  String get path => _innerDb.path;

  @override
  Future<void> close() => _innerDb.close();

  @override
  bool get isOpen => _innerDb.isOpen;

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) => _innerDb.transaction<T>(
    (txn) => action(FailingTransaction(txn, _plan)),
    exclusive: exclusive,
  );

  @override
  Future<T> readTransaction<T>(Future<T> Function(Transaction txn) action) =>
      _innerDb.readTransaction<T>(
        (txn) => action(FailingTransaction(txn, _plan)),
      );

  @override
  // ignore: deprecated_member_use
  Future<T> devInvokeMethod<T>(String method, [Object? arguments]) =>
      // ignore: deprecated_member_use
      _innerDb.devInvokeMethod<T>(method, arguments);

  @override
  // ignore: deprecated_member_use
  Future<T> devInvokeSqlMethod<T>(
    String method,
    String sql, [
    List<Object?>? arguments,
  ]) =>
      // ignore: deprecated_member_use
      _innerDb.devInvokeSqlMethod<T>(method, sql, arguments);
}
