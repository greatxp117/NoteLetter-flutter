import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/activity_item.dart';
import '../models/chunk.dart';
import '../models/cloud_folder.dart';
import '../models/document.dart';
import '../models/import_job.dart';
import '../models/newsletter.dart';
import '../models/organization_settings.dart';
import '../models/organization_suggestion.dart';
import '../models/newsletter_settings.dart';
import '../models/tag.dart';
import 'activity_merge.dart';
import 'auth_service.dart';

/// Direct Firestore access (INV-02): documents/activity/tags are realtime
/// subscriptions; newsletters/settings/import jobs are one-shot reads.
/// Every query filters `where('user_id', '==', uid)` — mirrors web `api.js`.
class FirestoreService {
  static final FirestoreService instance = FirestoreService._();
  FirestoreService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  String? get _uid => AuthService.instance.currentUser?.uid;

  /// Realtime document list, newest first. Strips `embedding` if present.
  Stream<List<Document>> subscribeDocuments({int limit = 200}) {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _db
        .collection('documents')
        .where('user_id', isEqualTo: uid)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = Map<String, dynamic>.from(d.data());
              data.remove('embedding');
              return Document.fromJson(d.id, data);
            }).toList());
  }

  /// Realtime tags list. Strips `embedding` (INV-05).
  Stream<List<Tag>> subscribeTags() {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _db
        .collection('tags')
        .where('user_id', isEqualTo: uid)
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = Map<String, dynamic>.from(d.data());
              data.remove('embedding');
              return Tag.fromJson(d.id, data);
            }).toList());
  }

  /// Realtime cloud import jobs (INV-02, 1.2.4): `user_id ==`, `created_at
  /// desc`, limit 50; aggregate/filter by provider client-side. Read-only —
  /// the Cloud Tasks workers own writes.
  Stream<List<ImportJob>> subscribeCloudImportJobs({int limit = 50}) {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _db
        .collection('cloud_import_jobs')
        .where('user_id', isEqualTo: uid)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => ImportJob.fromJson(d.id, d.data())).toList());
  }

  /// Realtime pending organization suggestions (1.2.0): `user_id ==`,
  /// `status == "pending"`, `created_at desc`. Read-only; resolve via the
  /// endpoint (INV-13). Audit/other-status views are one-shot elsewhere.
  Stream<List<OrganizationSuggestion>> subscribeOrganizationSuggestions() {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _db
        .collection('organization_suggestions')
        .where('user_id', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => OrganizationSuggestion.fromJson(d.id, d.data()))
            .toList());
  }

  /// Realtime organized-folder tree for a provider (1.2.0): `user_id ==`,
  /// `provider ==`. Strips `charter.embedding` (INV-05).
  Stream<List<CloudFolder>> subscribeCloudFolders(String provider) {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _db
        .collection('cloud_folders')
        .where('user_id', isEqualTo: uid)
        .where('provider', isEqualTo: provider)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = Map<String, dynamic>.from(d.data());
              final charter = (data['charter'] as Map?)?.cast<String, dynamic>();
              if (charter != null) {
                charter.remove('embedding');
                data['charter'] = charter;
              }
              return CloudFolder.fromJson(d.id, data);
            }).toList());
  }

  /// One-shot read of `/users/{uid}/settings/organization` (INV-02 — GET is not
  /// served; clients read the doc directly).
  Future<OrganizationSettings> getOrganizationSettings() async {
    final uid = _uid;
    if (uid == null) return const OrganizationSettings();
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('organization')
        .get();
    if (!snap.exists) return const OrganizationSettings();
    return OrganizationSettings.fromJson(snap.data()!);
  }

  /// Canonical activity merge (spec/screens/activity.md): activity_events +
  /// documents not covered by an event's `metadata.doc_id`, sorted by
  /// `created_at desc`, capped at [maxItems].
  Stream<List<ActivityItem>> subscribeActivity({int maxItems = 100}) {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);

    final controller = StreamController<List<ActivityItem>>.broadcast();
    List<ActivityItem> eventItems = [];
    List<ActivityItem> docItems = [];

    void emitMerged() {
      controller.add(mergeActivity(eventItems, docItems, maxItems: maxItems));
    }

    final eventsSub = _db
        .collection('activity_events')
        .where('user_id', isEqualTo: uid)
        .orderBy('created_at', descending: true)
        .limit(maxItems)
        .snapshots()
        .listen((snap) {
      eventItems = snap.docs.map((d) {
        final data = d.data();
        return ActivityItem(
          kind: 'event',
          id: d.id,
          type: data['type'] as String? ?? '',
          status: data['status'] as String? ?? '',
          title: data['title'] as String? ?? '',
          provider: data['provider'] as String?,
          errorMessage: null,
          metadata: data['metadata'] as Map<String, dynamic>?,
          createdAt: tsMs(data['created_at']),
        );
      }).toList();
      emitMerged();
    }, onError: (_) => controller.add(const []));

    final docsSub = _db
        .collection('documents')
        .where('user_id', isEqualTo: uid)
        .orderBy('created_at', descending: true)
        .limit(maxItems)
        .snapshots()
        .listen((snap) {
      docItems = snap.docs.map((d) {
        final data = d.data();
        return ActivityItem(
          kind: 'document',
          id: d.id,
          type: data['type'] as String? ?? '',
          status: data['status'] as String? ?? '',
          title: data['title'] as String? ?? 'Untitled',
          provider: null,
          errorMessage: data['error_message'] as String?,
          metadata: {
            'chunk_count': data['chunk_count'],
            'word_count': data['word_count'],
            'thumbnail_url': data['thumbnail_url'],
            'processed_at': tsMs(data['processed_at']),
          },
          createdAt: tsMs(data['created_at']),
        );
      }).toList();
      emitMerged();
    }, onError: (_) => controller.add(const []));

    controller.onCancel = () {
      eventsSub.cancel();
      docsSub.cancel();
    };

    return controller.stream;
  }

  /// One-shot read of `/users/{uid}/settings/newsletter`, strips
  /// `purposeEmbedding` (INV-05).
  Future<NewsletterSettings> getNewsletterSettings() async {
    final uid = _uid;
    if (uid == null) return const NewsletterSettings();
    final snap =
        await _db.collection('users').doc(uid).collection('settings').doc('newsletter').get();
    if (!snap.exists) return const NewsletterSettings();
    final data = Map<String, dynamic>.from(snap.data()!);
    data.remove('purposeEmbedding');
    return NewsletterSettings.fromJson(data);
  }

  /// Latest newsletter by recency (INV-09) — never construct `{uid}_{date}` IDs.
  Future<Newsletter?> getLatestNewsletter() async {
    final list = await listNewsletters(limit: 1);
    return list.isEmpty ? null : list.first;
  }

  /// Newsletter history by `generated_at desc` (INV-09).
  Future<List<Newsletter>> listNewsletters({int limit = 30}) async {
    final uid = _uid;
    if (uid == null) return const [];
    final snap = await _db
        .collection('newsletters')
        .where('user_id', isEqualTo: uid)
        .orderBy('generated_at', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map((d) => Newsletter.fromJson(d.id, d.data())).toList();
  }

  /// Reader: one-shot doc + its chunks (`chunk_index` asc). Fires
  /// `logReadEvent('doc_opened', ...)` — fire-and-forget (INV-03).
  Future<(Document, List<Chunk>)?> getReaderDocument(String docId) async {
    final result = await _fetchReaderDocument(docId);
    if (result != null) unawaited(logReadEvent('doc_opened', docId));
    return result;
  }

  /// Same reads as [getReaderDocument] but WITHOUT logging `doc_opened` — used
  /// to refresh the open reader after a content edit / reorganization rewrites
  /// chunks (INV-03: one +1 per open, not per reload).
  Future<(Document, List<Chunk>)?> getReaderDocumentQuietly(String docId) =>
      _fetchReaderDocument(docId);

  Future<(Document, List<Chunk>)?> _fetchReaderDocument(String docId) async {
    final uid = _uid;
    if (uid == null) return null;
    final snap = await _db.collection('documents').doc(docId).get();
    if (!snap.exists) return null;
    final data = Map<String, dynamic>.from(snap.data()!);
    data.remove('embedding');
    final document = Document.fromJson(snap.id, data);

    final chunksSnap = await _db
        .collection('chunks')
        .where('document_id', isEqualTo: docId)
        .where('user_id', isEqualTo: uid)
        .orderBy('chunk_index')
        .get();
    final chunks = chunksSnap.docs.map((c) {
      final cd = Map<String, dynamic>.from(c.data());
      cd.remove('embedding');
      cd['chunk_id'] = c.id;
      return Chunk.fromJson(cd);
    }).toList();

    return (document, chunks);
  }

  /// Chunk context window ±2 around [chunkId] (Reader chunk-context panel).
  /// Fires `logReadEvent('chunk_viewed', ...)` — fire-and-forget (INV-03).
  Future<List<Chunk>> getChunkContext(String chunkId) async {
    final uid = _uid;
    if (uid == null) return const [];
    final centerSnap = await _db.collection('chunks').doc(chunkId).get();
    if (!centerSnap.exists) return const [];
    final center = centerSnap.data()!;
    if (center['user_id'] != uid) return const [];
    final documentId = center['document_id'] as String;
    final idx = center['chunk_index'] as int;

    final ctxSnap = await _db
        .collection('chunks')
        .where('document_id', isEqualTo: documentId)
        .where('user_id', isEqualTo: uid)
        .where('chunk_index', isGreaterThanOrEqualTo: idx - 2)
        .where('chunk_index', isLessThanOrEqualTo: idx + 2)
        .orderBy('chunk_index')
        .get();
    final chunks = ctxSnap.docs.map((c) {
      final cd = Map<String, dynamic>.from(c.data());
      cd.remove('embedding');
      cd['chunk_id'] = c.id;
      return Chunk.fromJson(cd);
    }).toList();

    unawaited(logReadEvent('chunk_viewed', documentId, chunkId));
    return chunks;
  }

  /// Reading history for one document (Reader → History panel): the
  /// `read_events` for [docId], `created_at desc`, limit 50 (INV-02 —
  /// `user_id ==` filter). Timestamps → epoch ms (INV-06).
  Future<List<Map<String, dynamic>>> getReadHistory(String docId) async {
    final uid = _uid;
    if (uid == null) return const [];
    final snap = await _db
        .collection('read_events')
        .where('user_id', isEqualTo: uid)
        .where('document_id', isEqualTo: docId)
        .orderBy('created_at', descending: true)
        .limit(50)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      return {
        'id': d.id,
        'event_type': data['event_type'],
        'chunk_id': data['chunk_id'],
        'created_at': tsMs(data['created_at']),
      };
    }).toList();
  }

  /// Live `/reorg_plans/{planId}` subscription (Reorganize sheet): tracks
  /// `status` (`executing → done | failed`) as the backend rewrites chunks
  /// under the reader (INV-02 — a doc subscription, never a poll).
  Stream<Map<String, dynamic>?> subscribeReorgPlan(String planId) {
    return _db.collection('reorg_plans').doc(planId).snapshots().map((snap) {
      if (!snap.exists) return null;
      return Map<String, dynamic>.from(snap.data()!);
    });
  }

  /// The ONE sanctioned transaction that bumps `view_count`/`last_viewed_at`
  /// and writes the matching `read_events` doc (INV-03). Fire-and-forget —
  /// a failed log must never block the UI.
  Future<void> logReadEvent(String eventType, String documentId,
      [String? chunkId]) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _db.runTransaction((tx) async {
        final docRef = _db.collection('documents').doc(documentId);
        final docSnap = await tx.get(docRef);
        tx.update(docRef, {
          'view_count': ((docSnap.data()?['view_count'] as int?) ?? 0) + 1,
          'last_viewed_at': FieldValue.serverTimestamp(),
        });

        if (chunkId != null) {
          final chunkRef = _db.collection('chunks').doc(chunkId);
          final chunkSnap = await tx.get(chunkRef);
          tx.update(chunkRef, {
            'view_count': ((chunkSnap.data()?['view_count'] as int?) ?? 0) + 1,
            'last_viewed_at': FieldValue.serverTimestamp(),
          });
        }

        final eventRef = _db.collection('read_events').doc();
        tx.set(eventRef, {
          'user_id': uid,
          'event_type': eventType,
          'document_id': documentId,
          'chunk_id': chunkId,
          'created_at': FieldValue.serverTimestamp(),
        });
      });
    } catch (_) {
      // Fire-and-forget — never block the UI on a failed read-tracking write.
    }
  }
}
