// ignore_for_file: avoid_print
//
// Generates `web/sitemap.xml` from the live `docsTree` + `examplesTree`
// structures so the sitemap never drifts from the actual set of pages.
//
// Run locally before committing tree changes, or from CI right before
// `flutter build web`:
//
//   dart run tool/generate_sitemap.dart
//
// The output is deterministic (lastmod uses the current UTC date in
// `YYYY-MM-DD`), so re-runs on an unchanged tree produce no diff past
// the date bump.

import 'dart:io';

import 'package:armature_website/docs/docs_tree.dart';
import 'package:armature_website/examples/examples_tree.dart';

const _baseUrl = 'https://telchardev.github.io/armature';

void main() {
  final today = DateTime.now().toUtc().toIso8601String().split('T').first;

  final entries = <({String loc, double priority})>[
    (loc: '$_baseUrl/', priority: 1.0),
    for (final section in docsTree)
      for (final entry in section.entries)
        (loc: '$_baseUrl/docs/${entry.slug}', priority: 0.9),
    for (final section in examplesTree)
      for (final entry in section.entries)
        (loc: '$_baseUrl/examples/${entry.slug}', priority: 0.8),
  ];

  final buf = StringBuffer();
  buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  buf.writeln('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">');
  for (final e in entries) {
    buf.writeln('  <url>');
    buf.writeln('    <loc>${e.loc}</loc>');
    buf.writeln('    <lastmod>$today</lastmod>');
    buf.writeln('    <changefreq>weekly</changefreq>');
    buf.writeln('    <priority>${e.priority.toStringAsFixed(1)}</priority>');
    buf.writeln('  </url>');
  }
  buf.writeln('</urlset>');

  File('web/sitemap.xml').writeAsStringSync(buf.toString());
  print('Wrote ${entries.length} URLs to web/sitemap.xml');
}
