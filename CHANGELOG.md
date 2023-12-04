# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.1.0

### Fixed

- response-expires header format match recent AWS ruby SDK by using #httpdate https://github.com/jrochkind/faster_s3_url/pull/5


### Changed

- Some decrease in memory allocations made by gem https://github.com/jrochkind/faster_s3_url/pull/6
