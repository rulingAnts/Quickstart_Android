# Smoke-testing the phone app without a phone

How to run the CI-built APK on an emulator, including task mode with
`test_data/sample_task/sample.dektask`.

## Where to install the emulator

- **Mac host: yes.** Install Android Studio directly on macOS. On Apple
  Silicon the ARM system images run natively and are quick.
- **Inside the Parallels Windows VM: no.** The Android emulator is itself
  a virtual machine; nested virtualization under Parallels either won't
  start or is unusably slow. (Same caution for any VM.)

## One-time setup (~15 min, ~12 GB disk)

1. Install Android Studio (developer.android.com/studio). You will NOT
   need to open the project or write code — only the device manager.
2. On the welcome screen: **More Actions → Virtual Device Manager →
   Create virtual device**.
3. Pick any recent phone (e.g. Pixel 8), accept the suggested system
   image (download it when prompted), finish, and press ▶ to boot it.

## Each test run (~10 min)

1. Download the latest `wordlist-elicitation-apk` artifact from the
   repo's **Actions** tab (newest green run) and unzip it to get
   `app-release.apk`.
2. **Drag `app-release.apk` onto the emulator window** — it installs
   automatically. Find "Wordlist Elicitation Tool" in the app drawer.
3. Get the sample task in: **drag `sample.dektask` onto the emulator
   window** too — it lands in the emulator's `Downloads` folder.
4. In the app: **Import Wordlist → browse to Downloads →
   `sample.dektask`**, then follow
   [`test_data/sample_task/README.md`](../test_data/sample_task/README.md).
5. To test **recording**, give the emulator a microphone first:
   emulator side toolbar **⋯ (Extended controls) → Microphone → enable
   "Virtual microphone uses host audio input"**, and accept the app's
   mic permission prompt. Play/record a word, then **Export My Answers**
   and share the `.dekresult` (easiest: the Files app → share → Drive,
   or `adb pull` if you have the command line set up).

## Zero-install alternative (quick look only)

appetize.io runs APKs in the browser (free tier, ~30 min/month): upload
`app-release.apk`, launch, click around. Fine for checking screens;
file import and microphone testing are much easier on a real AVD.

## What to check (both modes)

- Plain mode: import a Dekereke `.xml`, elicit a word (type + record),
  export the ZIP.
- Task mode: import `sample.dektask` → prompts show Gloss + Indonesian,
  the Listen button plays the reference tones on records 0001/0002/0003/
  0005 (0004/0006 have none on purpose), the Yohanis section takes text
  and a recording, and **Export My Answers** produces a `.dekresult`.
- PR #5's pending device smoke test is covered by the plain-mode pass.
