# Updating the vendored TagLib

TagLibSwift compiles TagLib from source that is **vendored** directly into
this repository (`Sources/CTagLib/taglib/` and `Sources/CTagLib/utfcpp/`).
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
   rm -rf Sources/CTagLib/taglib && cp -R taglib/taglib Sources/CTagLib/taglib
   rm -rf Sources/CTagLib/utfcpp && cp -R taglib/3rdparty/utfcpp/source Sources/CTagLib/utfcpp
   ```

3. **Strip non-source files from the fresh copy**

   The upstream tree carries CMake build files that aren't needed (and
   shouldn't ship) in the vendored copy:

   ```bash
   find Sources/CTagLib/taglib \( -name 'CMakeLists.txt' -o -name '*.cmake' -o -name 'Makefile*' \) -delete
   ```

4. **Regenerate the config headers**

   `Sources/CTagLib/config/` holds `config.h` and `taglib_config.h`, which
   TagLib's CMake build normally generates. Regenerate them against the new
   tag with a throwaway CMake configure (this does not need to succeed at
   building, just at configuring):

   ```bash
   cmake -S taglib -B /tmp/taglib-config-gen -DCMAKE_BUILD_TYPE=Release -DBUILD_BINDINGS=OFF
   ```

   Copy the generated `config.h` and `taglib_config.h` from
   `/tmp/taglib-config-gen` into `Sources/CTagLib/config/`, replacing the
   existing copies. Before committing, **diff the new files against the old
   ones** and strip any machine-local absolute paths that leak in (e.g. a
   `TESTS_DIR` define pointing at the build machine's checkout) — those must
   not be checked in. Confirm `HAVE_ZLIB` (and any other feature macros the
   build previously relied on) are still defined as expected.

5. **Reconcile header search paths**

   `Package.swift`'s `CTagLib` target declares explicit header search paths
   into the vendored TagLib tree (`cSettings`/`cxxSettings` `headerSearchPath`
   entries). New releases occasionally add or remove subdirectories, so
   regenerate the directory list and diff it against what's currently in
   `Package.swift`:

   ```bash
   find Sources/CTagLib/taglib -type d
   ```

   Add any new directories that contain headers TagLib's own sources
   `#include`, and remove any that no longer exist.

6. **Leave the bridge alone (usually)**

   `Sources/CTagLib/bridge/taglib_c_bridge.cpp` and its public header
   `Sources/CTagLib/include/taglib_c_bridge.h` are TagLibSwift's own thin C
   wrapper, not vendored code — they don't need updating for a version bump
   unless the new TagLib release changed a C++ API the bridge calls. If it
   did, update the bridge accordingly and keep its public surface (`extern
   "C"`, `TagFile`/`TagLibError`) unchanged so the Swift-facing API stays
   backward compatible.

7. **Build and test**

   ```bash
   swift build && swift test
   ```

   Then confirm the iOS simulator build still works:

   ```bash
   xcodebuild -scheme TagLibSwift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
   ```

8. **Commit**

   Commit the updated submodule pointer, `.gitmodules`, the re-vendored
   source, regenerated config headers, and any `Package.swift` header search
   path changes together as one change.
