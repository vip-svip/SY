# FX Hook migration next steps

The legacy hook source is available in the Iter5 archive. The migration must preserve feature switches and package scope while porting API 82 callbacks to libxposed API 101. The two APIs are not source-compatible. Do not claim a unified APK until CI builds it and device injection is verified.

Configuration must be read through LSPosed Remote Files, parsed transactionally, and support independent ad and privacy switches. Invalid or missing configuration must disable hooks safely.
