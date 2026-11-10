# GPKit on Android: a feasibility note

For the owner's review (2026-11-10), on branch `v2-android-note`. Nothing was installed for it. It reads GPKit's own
CI, main's run 42849519141 at 1f5405b (1.3.0). Claims that no run has shown are marked **[untested]** or
**[inferred]**.

## What is shown

- **The package builds and its tests pass on Android.** In the job "build, test (Android, Swift 6.4.2)" all 123 tests
  pass in 25 suites, the Vallado epoch tests and GPKitSources' tests among them. They ran in an Android emulator,
  x86_64, API level 28.
- **The toolchain.** The job uses swift.org's own Android SDK for 6.4.2 (`swift-6.4.2-RELEASE_android.artifactbundle`),
  linked to the runner's NDK 27.3. It runs through `skiptools/swift-android-action` v2.9.5, pinned by commit. It took
  3 min 48 s.
- **The core needs nothing Android lacks.** GPKit is Swift with no dependency, and only `Date.swift` bridges to
  Foundation. GPKitSources builds there too, `URLSessionTransport` included, though no test makes a request.

## What is not shown

- **Phones.** Phones are arm64-v8a, and CI builds only x86_64 for the emulator. **[untested]** The action takes the
  architecture from the runner, so an arm64 Linux runner would build arm64 **[inferred]**.
- **Size.** No release build of the library for Android has been measured. A program that links Foundation carries
  Foundation's libraries in the app, and their size there is not known **[untested]**. The core without
  `Date.swift`, as the playground builds it, would avoid that **[inferred]**.
- **Google Play's 16 KB pages.** Play asks apps targeting recent Android versions to support 16 KB memory pages. No
  check has been made of whether the SDK's libraries and GPKit's are aligned for it **[untested]**.
- **Calling it from an app.** An Android app is Kotlin or Java, and GPKit has no interface for them yet. Two ways are
  known:
  - a small C interface (`@_cdecl` functions, JSON in and out, as the playground's WebAssembly module already
    offers), called through JNI;
  - swift-java's generated bindings.

  Neither has been built here **[untested]**.
- **GP Passes.** The app's screens are SwiftUI, which does not exist on Android. Notifications and widgets are
  Apple's own frameworks. An Android GP Passes would share GPKit and its sun model, and rebuild every screen
  natively.

## A path, each step proved before the next

1. **Build for arm64.** Add an arm64 Android job to CI, on an arm64 runner, with the same action and the same tests.
   It is done when its tests pass.
2. **Measure a release library.** Build `libGPKit.so` with a minimal C interface: the playground's calls (read, now,
   passes) as JSON. Measure its size with and without Foundation, and check the 16 KB alignment with the NDK's own
   tools in CI. It is done when the sizes are recorded and the alignment is checked.
3. **Build a sample Android app.** A Kotlin sample that calls the library through JNI and shows the next passes for a
   held TLE. Its answers must match GPKit's native ones within 1e-9, as the playground's do. It is done when the
   comparison runs in CI's emulator.
4. **Decide on an Android GP Passes**, from steps 2 and 3's numbers. That decision is the owner's.

Steps 1 and 2 are CI work on branches only, with no install on this Mac. Step 3 would need an Android app build in
CI, Gradle from Google's Maven, which is a new dependency for the owner to allow.

## Questions for the owner

- Is an arm64 Android job (step 1) wanted in GPKit's CI? It adds a job of about 4 minutes to each push. GPKit is
  public, so Actions minutes cost nothing.
- Should GPKit's Android interface be the playground's JSON calls (one design for the web and Android), or typed
  bindings through swift-java?
