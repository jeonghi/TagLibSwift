# Updating the vendored TagLib

TagLibSwift compiles TagLib from source that is **vendored** directly into
this repository (`Sources/CTagLibCore/taglib/` and `Sources/CTagLibCore/utfcpp/`).
Consumers of the package never need the `taglib` git submodule — it exists
purely as the maintainer's source-of-truth checkout for producing the next
vendored drop. Follow this procedure whenever TagLib needs to be bumped to a
new release.

1. **Check out the new TagLib tag in the submodule**

   ```bash
   cd taglib && git fetch --tags && git checkout vX.Y.Z && cd ..
   ```

   Update `.gitmodules`' `branch = vX.Y.Z` to match.

2. **Re-copy the vendored source**

   ```bash
   rm -rf Sources/CTagLibCore/taglib && cp -R taglib/taglib Sources/CTagLibCore/taglib
   rm -rf Sources/CTagLibCore/utfcpp && cp -R taglib/3rdparty/utfcpp/source Sources/CTagLibCore/utfcpp
   ```

3. **Strip non-source files from the fresh copy**

   The upstream tree carries CMake build files that aren't needed (and
   shouldn't ship) in the vendored copy:

   ```bash
   find Sources/CTagLibCore/taglib \( -name 'CMakeLists.txt' -o -name '*.cmake' -o -name 'Makefile*' \) -delete
   ```

4. **Regenerate the config headers**

   `Sources/CTagLibCore/config/` holds `config.h` and `taglib_config.h`, which
   TagLib's CMake build normally generates. Regenerate them against the new
   tag with a throwaway CMake configure (this does not need to succeed at
   building, just at configuring):

   ```bash
   cmake -S taglib -B /tmp/taglib-config-gen -DCMAKE_BUILD_TYPE=Release -DBUILD_BINDINGS=OFF
   ```

   Copy the generated `config.h` and `taglib_config.h` from
   `/tmp/taglib-config-gen` into `Sources/CTagLibCore/config/`, replacing the
   existing copies. Before committing, **diff the new files against the old
   ones** and strip any machine-local absolute paths that leak in (e.g. a
   `TESTS_DIR` define pointing at the build machine's checkout) — those must
   not be checked in. Confirm `HAVE_ZLIB` (and any other feature macros the
   build previously relied on) are still defined as expected.

5. **Reconcile header search paths**

   `Package.swift`'s `CTagLibCore` target declares explicit header search paths
   into the vendored TagLib tree (`taglibInternalHeaderPaths`, applied as
   `cxxSettings` `headerSearchPath` entries). These are for compiling
   CTagLibCore's own `.cpp` only. New releases occasionally add or remove
   subdirectories, so regenerate the directory list and diff it against what's
   currently in `Package.swift`:

   ```bash
   find Sources/CTagLibCore/taglib -type d
   ```

   Add any new directories that contain headers TagLib's own sources
   `#include`, and remove any that no longer exist.

6. **Regenerate the flat public headers**

   The dependent target (`TagLibSwift`) does NOT see
   CTagLibCore's internal header search paths — SwiftPM only exposes a target's
   `publicHeadersPath`. So every public TagLib header is flattened into
   `Sources/CTagLibCore/include/taglib/` (mirroring `make install`) by a script.
   Regenerate it after re-vendoring:

   ```bash
   ./scripts/generate-flat-headers.sh
   ```

   The script aborts on a header basename collision (the flat layout can't
   represent one). If TagLib ever ships two same-named headers, the flat-header
   strategy and `Sources/CTagLibCore/include/module.modulemap` need revisiting.
   Also review `Sources/CTagLibCore/include/taglib_interop.h` if any C++ type it
   references (FileRef, Tag, AudioProperties, PropertyMap, VariantMap) changed.

7. **Review the interop helpers (usually no change)**

   `Sources/CTagLibCore/include/taglib_interop.h` holds the small inline C++
   helpers the Swift `TagLibSwift` target calls over Swift/C++ interop. They
   don't need updating for a version bump unless the new TagLib release changed
   a C++ API they call. If it did, update the helper and keep its signature
   stable so the Swift-facing API stays backward compatible.

8. **Build and test**

   ```bash
   swift build && swift test
   ```

   Then confirm the iOS simulator build still works:

   ```bash
   xcodebuild -scheme TagLibSwift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
   ```

9. **Commit**

   Commit the updated submodule pointer, `.gitmodules`, the re-vendored
   source, regenerated config headers, and any `Package.swift` header search
   path changes together as one change.
