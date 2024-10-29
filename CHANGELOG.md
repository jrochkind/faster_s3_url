# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.2.0

### Changed

- Now requires at least ruby 3.1
- uses CGI.escapeURIComponent for somewhat improved performance https://github.com/jrochkind/faster_s3_url/pull/8

### Added

- Add `session_token` option to `Builder` from [@BenKanouse](https://github.com/BenKanouse) https://github.com/jrochkind/faster_s3_url/pull/12

- Add 'endpoint' option to Builder, thanks @BenKanouse, https://github.com/jrochkind/faster_s3_url/pull/14

## 1.1.0

### Fixed

- response-expires header format match recent AWS ruby SDK by using #httpdate https://github.com/jrochkind/faster_s3_url/pull/5

- Only define local Storage#object_key if Shrine isn't already providing https://github.com/jrochkind/faster_s3_url/pull/7

### Changed

- Some decrease in memory allocations made by gem https://github.com/jrochkind/faster_s3_url/pull/6
