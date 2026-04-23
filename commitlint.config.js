// Commit message lint rules.
//
// Source of truth for the CI check (wagoid/commitlint-github-action)
// and a reference for the local bash pre-commit hook in lefthook.yml.
//
// Format — Conventional Commits:
//   <type>(<scope>): <subject>
//
//   [optional body]
//
//   [optional footer, including BREAKING CHANGE: <description>]
//
// Allowed types: feat, fix, docs, style, refactor, perf, test,
// build, ci, chore, revert, release.
//
// Scope is optional. Common scopes in this repo:
//   armature, armature_flutter, armature_graph, armature_reactive,
//   example, website, ci, deps, release, workspace.
module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    // Conventional default is 72 — slightly too tight for descriptive
    // messages. 100 leaves room without inviting essays.
    'header-max-length': [2, 'always', 100],
    'body-max-line-length': [2, 'always', 100],
  },
};
