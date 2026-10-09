"""Live SwiftUI preview on Windows.

Usage: python preview.py <ios-project-dir>

Watches the project's .swift files, copies them (minus the @main App file) into
the PreviewHost target, rewrites `#Preview { ... }` blocks into functions,
rebuilds and relaunches the iPhone-framed preview window on every save.
"""
import os, re, subprocess, sys, time, shutil

ROOT = os.path.dirname(os.path.abspath(__file__))
HOST = os.path.join(ROOT, "Sources", "PreviewHost")
SWIFT_HOME = os.path.join(os.environ["LOCALAPPDATA"], "Programs", "Swift")
ENV = dict(os.environ)
ENV["SDKROOT"] = os.path.join(SWIFT_HOME, "Platforms", "6.4.0", "Windows.platform", "Developer", "SDKs", "Windows.sdk") + "\\"
ENV["PATH"] = os.pathsep.join([
    os.path.join(SWIFT_HOME, "Toolchains", "6.4.0+Asserts", "usr", "bin"),
    os.path.join(SWIFT_HOME, "Runtimes", "6.4.0", "usr", "bin"),
    ENV["PATH"],
])

def find_msvc_tools():
    """Newest MSVC toolset on disk. Needed when Visual Studio's setup registry is broken
    (vswhere finds nothing): clang then can't locate the C runtime headers on its own."""
    import glob
    hits = []
    for root in (os.environ.get("ProgramFiles", r"C:\Program Files"), os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")):
        hits += glob.glob(os.path.join(root, "Microsoft Visual Studio", "*", "*", "VC", "Tools", "MSVC", "*"))
    return sorted(hits)[-1] + "\\" if hits else None


if "VCToolsInstallDir" not in ENV:
    tools = find_msvc_tools()
    if tools:
        ENV["VCToolsInstallDir"] = tools

PREVIEW_RE = re.compile(r'#Preview\s*(\([^)]*\))?\s*\{')


def swift_files(project):
    out = []
    for dirpath, dirs, files in os.walk(project):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d not in ("xtool", ".build")]
        out += [os.path.join(dirpath, f) for f in files if f.endswith(".swift") and f != "Package.swift"]
    return sorted(out)


def snapshot(files):
    return {f: os.stat(f).st_mtime for f in files}


def matching_brace(src, open_idx):
    depth = 0
    i = open_idx
    while i < len(src):
        c = src[i]
        if c == '"':                     # skip string literals
            i += 1
            while i < len(src) and src[i] != '"':
                i += 2 if src[i] == "\\" else 1
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ValueError("unbalanced braces in #Preview")


def rewrite_previews(src, counter):
    """#Preview { body }  ->  @ViewBuilder func __preview_N() -> some View { body }"""
    names = []
    while True:
        m = PREVIEW_RE.search(src)
        if not m:
            return src, names
        close = matching_brace(src, m.end() - 1)
        body = src[m.end():close]
        name = f"__preview_{counter[0]}"
        counter[0] += 1
        names.append(name)
        src = src[:m.start()] + f"@ViewBuilder func {name}() -> some View {{{body}}}" + src[close + 1:]


def stage(project):
    for f in os.listdir(HOST):
        os.remove(os.path.join(HOST, f))
    previews, counter, has_content_view = [], [0], False
    for path in swift_files(project):
        src = open(path, encoding="utf-8").read()
        if re.search(r"^\s*@main\b", src, re.M):
            continue                      # the App entry point is replaced by our host
        src, names = rewrite_previews(src, counter)
        previews += names
        has_content_view |= bool(re.search(r"\bstruct\s+ContentView\b", src))
        with open(os.path.join(HOST, os.path.basename(path)), "w", encoding="utf-8") as out:
            out.write(src)
    target = f"{previews[0]}()" if previews else ("ContentView()" if has_content_view else None)
    if not target:
        raise RuntimeError("No #Preview block or ContentView found")
    title = os.path.basename(os.path.normpath(project)) + " — Preview"
    import json
    with open(os.path.join(HOST, "_PreviewEntry.swift"), "w", encoding="utf-8") as out:
        entry = [
            "import SwiftUI",
            "",
            "@main",
            "struct __PreviewEntry {",
            "    static func main() {",
            f"        Runtime.runPreview(title: {json.dumps(title, ensure_ascii=False)}) {{ {target} }}",
            "    }",
            "}",
        ]
        out.write(chr(10).join(entry) + chr(10))
    return target


def build():
    t = time.time()
    swift = os.path.join(SWIFT_HOME, "Toolchains", "6.4.0+Asserts", "usr", "bin", "swift.exe")
    # The classic build system honours VCToolsInstallDir (the newer one ignores it)
    r = subprocess.run([swift, "build", "--build-system", "native", "--product", "PreviewHost"], cwd=ROOT, env=ENV,
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    lines = re.sub(r"\x1b\[[0-9;]*m", "", r.stdout + r.stderr).splitlines()
    errors = list(dict.fromkeys(l for l in lines if "error:" in l and "nonzero exit code" not in l))
    return r.returncode == 0, time.time() - t, errors


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    project = sys.argv[1]
    exe = os.path.join(ROOT, ".build", "debug", "PreviewHost.exe")
    proc, last = None, None
    print(f"Watching {project}  (Ctrl+C to quit)")
    while True:
        files = swift_files(project)
        snap = snapshot(files)
        if snap != last:
            last = snap
            try:
                target = stage(project)
            except Exception as e:
                print(f"[!] {e}")
                time.sleep(1)
                continue
            ok, secs, errors = build()
            if ok:
                if proc and proc.poll() is None:
                    proc.kill()
                    proc.wait()
                # Run a copy so the next build can overwrite the linked exe (Windows locks running images)
                run_dir = os.path.join(os.environ["TEMP"], "swiftui-preview")
                os.makedirs(run_dir, exist_ok=True)
                run_exe = os.path.join(run_dir, "PreviewHost.exe")
                shutil.copy2(exe, run_exe)
                proc = subprocess.Popen([run_exe], env=ENV, cwd=ROOT)
                print(f"[✓] {time.strftime('%H:%M:%S')} {target} built ({secs:.1f}s)")
            else:
                print(f"[x] {time.strftime('%H:%M:%S')} build failed:")
                for e in errors[:10]:
                    print("    " + e.split("PreviewHost\\")[-1])
        time.sleep(0.7)


if __name__ == "__main__":
    main()
