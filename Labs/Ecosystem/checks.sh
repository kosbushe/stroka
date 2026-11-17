#!/bin/zsh
set -euo pipefail
STROKA_CHECK_ROOT="${0:A:h}"
STROKA_CHECK_JAVA="${JAVA_HOME:?Set JAVA_HOME to a JDK 17+ installation}"
mkdir -p "$STROKA_CHECK_ROOT/Validation/java-tests" "$STROKA_CHECK_ROOT/Validation/ModuleCache"
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" -module-cache-path "$STROKA_CHECK_ROOT/Validation/ModuleCache" "$STROKA_CHECK_ROOT/Shared/Profile.swift" "$STROKA_CHECK_ROOT/Tests/ProfileChecks.swift" -o "$STROKA_CHECK_ROOT/Validation/profile-checks"
"$STROKA_CHECK_ROOT/Validation/profile-checks"
"$STROKA_CHECK_JAVA/bin/javac" -d "$STROKA_CHECK_ROOT/Validation/java-tests" "$STROKA_CHECK_ROOT/TV/src/ru/bushe/strokatv/FeedParser.java" "$STROKA_CHECK_ROOT/TV/src/ru/bushe/strokatv/PublicTLS.java" "$STROKA_CHECK_ROOT/Tests/FeedChecks.java"
"$STROKA_CHECK_JAVA/bin/java" -cp "$STROKA_CHECK_ROOT/Validation/java-tests" ru.bushe.strokatv.lab.FeedChecks
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" -module-cache-path "$STROKA_CHECK_ROOT/Validation/ModuleCache" "$STROKA_CHECK_ROOT/Shared/Profile.swift" "$STROKA_CHECK_ROOT/Apple/PinnedTransport.swift" "$STROKA_CHECK_ROOT/Tests/LinkChecks.swift" -o "$STROKA_CHECK_ROOT/Validation/link-checks"
echo "TLS fixture: python3 Tests/check_tls.py (opens a temporary local TLS listener)"
