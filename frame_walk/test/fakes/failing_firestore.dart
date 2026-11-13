import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

// FakeFirebaseFirestore whose next [failBatchCommits] batch commits fail
// without writing anything, the way a real batch is all or nothing.
// (FakeFirebaseFirestore's own batches apply writes one by one.)
class FailingBatchFirestore extends FakeFirebaseFirestore {
  int failBatchCommits = 0;

  @override
  WriteBatch batch() {
    final real = super.batch();
    if (failBatchCommits <= 0) return real;
    failBatchCommits--;
    return _FailingBatch();
  }
}

class _FailingBatch implements WriteBatch {
  @override
  Future<void> commit() async =>
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');

  @override
  void delete(DocumentReference document) {}

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) {}

  @override
  void update<T>(DocumentReference<T> document, T data) {}
}
