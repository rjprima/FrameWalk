import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:frame_walk/backend/services/gallery_pager.dart';
import 'package:frame_walk/backend/services/local_photo_service.dart';
import 'package:frame_walk/backend/services/photo_manager_photo_service.dart';
import 'package:photo_manager/photo_manager.dart';

import 'fakes/fake_local_photo_service.dart';

void main() {
  FakeLocalPhotoService galleryWith(int count) => FakeLocalPhotoService(
        gallery: List.generate(
          count,
          (i) => photoAt('p$i', DateTime(2026, 1, 1).add(Duration(minutes: i))),
        ),
      );

  GalleryPager pagerFor(FakeLocalPhotoService photos, {int pageSize = 10}) =>
      GalleryPager(
        (page, size) => photos.fetchPhotos(page: page, pageSize: size),
        pageSize: pageSize,
      );

  group('GalleryPager', () {
    test('loads one page at a time, newest first', () async {
      final photos = galleryWith(25);
      final pager = pagerFor(photos);

      await pager.loadNextPage();
      expect(pager.photos, hasLength(10));
      expect(pager.photos.first.assetId, 'p24');
      expect(pager.hasMore, isTrue);

      await pager.loadNextPage();
      await pager.loadNextPage();
      expect(pager.photos, hasLength(25));
      expect(pager.hasMore, isFalse);
      expect(photos.requestedPages, [0, 1, 2]);

      await pager.loadNextPage();
      expect(photos.requestedPages, [0, 1, 2], reason: 'no more pages');
    });

    test('handles an empty camera roll', () async {
      final pager = pagerFor(galleryWith(0));

      await pager.loadNextPage();

      expect(pager.photos, isEmpty);
      expect(pager.hasMore, isFalse);
      expect(pager.isLoading, isFalse);
    });

    test('ignores scroll requests while a page is loading', () async {
      final photos = galleryWith(30);
      final pager = pagerFor(photos);

      await Future.wait([pager.loadNextPage(), pager.loadNextPage()]);

      expect(photos.requestedPages, [0]);
    });

    test('skips photos repeated across pages', () async {
      final photos = galleryWith(15);
      final pager = pagerFor(photos);
      await pager.loadNextPage();

      // A new photo shifts everything down one place.
      photos.gallery.add(photoAt('new', DateTime(2026, 6, 1)));
      await pager.loadNextPage();

      final ids = pager.photos.map((p) => p.assetId).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('refresh starts again from the first page', () async {
      final photos = galleryWith(15);
      final pager = pagerFor(photos);
      await pager.loadNextPage();
      await pager.loadNextPage();

      await pager.refresh();

      expect(pager.photos, hasLength(10));
      expect(photos.requestedPages, [0, 1, 0]);
    });

    test('discards a page that finishes loading after a refresh', () async {
      final slowPage = Completer<GalleryPage>();
      var calls = 0;
      final pager = GalleryPager((page, size) {
        calls++;
        if (calls == 1) return slowPage.future;
        return Future.value(GalleryPage(
          photos: [photoAt('fresh', DateTime(2026))],
          page: page,
          hasMore: false,
        ));
      });

      final stale = pager.loadNextPage();
      await pager.refresh();
      slowPage.complete(GalleryPage(
        photos: [photoAt('stale', DateTime(2025))],
        page: 0,
        hasMore: true,
      ));
      await stale;

      expect(pager.photos.map((p) => p.assetId), ['fresh']);
    });

    test('recovers from a failed page load', () async {
      var fail = true;
      final pager = GalleryPager((page, size) async {
        if (fail) throw Exception('gallery unavailable');
        return GalleryPage(photos: const [], page: page, hasMore: false);
      });

      await pager.loadNextPage();
      expect(pager.isLoading, isFalse);
      expect(pager.hasMore, isTrue, reason: 'can try again');

      fail = false;
      await pager.loadNextPage();
      expect(pager.hasMore, isFalse);
    });

    test('returns nothing without photo access', () async {
      final photos = galleryWith(5)..access = GalleryAccess.denied;
      final pager = pagerFor(photos);

      await pager.loadNextPage();

      expect(pager.photos, isEmpty);
    });
  });

  group('Android permission states', () {
    test('full access', () {
      expect(
        PhotoManagerPhotoService.mapPermissionState(PermissionState.authorized),
        GalleryAccess.full,
      );
    });

    test('Android 14 selected-photos access is limited', () {
      expect(
        PhotoManagerPhotoService.mapPermissionState(PermissionState.limited),
        GalleryAccess.limited,
      );
      expect(GalleryAccess.limited.canRead, isTrue);
    });

    test('denied, revoked, and never-asked all mean no access', () {
      for (final state in [
        PermissionState.denied,
        PermissionState.notDetermined,
        PermissionState.restricted,
      ]) {
        final access = PhotoManagerPhotoService.mapPermissionState(state);
        expect(access, GalleryAccess.denied);
        expect(access.canRead, isFalse);
      }
    });
  });
}
