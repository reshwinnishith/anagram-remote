#!/usr/bin/env python3
"""Regenerates AnagramRemote.xcodeproj/project.pbxproj deterministically.
Run from the repo root after adding/removing source files:  python3 Tools/generate_xcodeproj.py
"""
import hashlib, os

def uid(s): return hashlib.md5(s.encode()).hexdigest()[:24].upper()

APP = [("App", ["AnagramRemoteApp.swift"]),
       ("Features/Connection", ["ConnectionView.swift", "ConnectionViewModel.swift"]),
       ("MIDI", ["MIDITransport.swift", "CoreMIDITransport.swift", "MIDICommand.swift", "MIDIConnectionManager.swift"]),
       ("Models", ["MIDIDestination.swift", "TransmissionRecord.swift"])]
TESTS = ["MockMIDITransport.swift", "MIDICommandTests.swift", "MIDIConnectionManagerTests.swift", "CoreMIDITransportInitializationTests.swift"]

out = []
w = out.append
files = []  # (path, fileref, buildfile, target)
for d, fs in APP:
    for f in fs: files.append((f"AnagramRemote/{d}/{f}", "app"))
for f in TESTS: files.append((f"AnagramRemote/Tests/{f}", "test"))
assets = "AnagramRemote/Resources/Assets.xcassets"

fr = lambda p: uid("fr:" + p); bf = lambda p: uid("bf:" + p)
PROJ, MAINGRP, APPGRP, TESTGRP, PRODGRP = map(uid, ["proj", "main", "appgrp", "testgrp", "prodgrp"])
APPT, TESTT = uid("apptarget"), uid("testtarget")
APPPROD, TESTPROD = uid("appprod"), uid("testprod")
SRC_A, SRC_T, RES_A = uid("srcA"), uid("srcT"), uid("resA")
FW_A, FW_T = uid("fwA"), uid("fwT")
CL_P, CL_A, CL_T = uid("clP"), uid("clA"), uid("clT")
CFG = {k: uid("cfg" + k) for k in ["PD", "PR", "AD", "AR", "TD", "TR"]}
DEP, PROXY = uid("dep"), uid("proxy")

w("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 56;\n\tobjects = {\n")
w("/* Begin PBXBuildFile section */")
for p, t in files: w(f"\t\t{bf(p)} = {{isa = PBXBuildFile; fileRef = {fr(p)}; }};")
w(f"\t\t{bf(assets)} = {{isa = PBXBuildFile; fileRef = {fr(assets)}; }};")
w("/* End PBXBuildFile section */\n")
w("/* Begin PBXContainerItemProxy section */")
w(f"\t\t{PROXY} = {{isa = PBXContainerItemProxy; containerPortal = {PROJ}; proxyType = 1; remoteGlobalIDString = {APPT}; remoteInfo = AnagramRemote; }};")
w("/* End PBXContainerItemProxy section */\n")
w("/* Begin PBXFileReference section */")
for p, t in files: w(f'\t\t{fr(p)} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{os.path.basename(p)}"; sourceTree = "<group>"; }};')
w(f'\t\t{fr(assets)} = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};')
w(f'\t\t{APPPROD} = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = AnagramRemote.app; sourceTree = BUILT_PRODUCTS_DIR; }};')
w(f'\t\t{TESTPROD} = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = AnagramRemoteTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};')
w("/* End PBXFileReference section */\n")
w("/* Begin PBXFrameworksBuildPhase section */")
for i in (FW_A, FW_T): w(f"\t\t{i} = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};")
w("/* End PBXFrameworksBuildPhase section */\n")

def group(gid, name, path, children):
    kids = ",".join(f"\n\t\t\t\t{c}" for c in children)
    return f'\t\t{gid} = {{isa = PBXGroup; children = ({kids}\n\t\t\t); name = "{name}"; path = "{path}"; sourceTree = "<group>"; }};'
w("/* Begin PBXGroup section */")
sub = []
appkids = []
for d, fs in APP:
    gid = uid("grp:" + d)
    # nested path groups
    sub.append(group(gid, d.split("/")[-1], d, [fr(f"AnagramRemote/{d}/{f}") for f in fs]))
    appkids.append(gid)
resg = uid("grp:Resources")
sub.append(group(resg, "Resources", "Resources", [fr(assets)]))
appkids.append(resg)
testkids = [fr(f"AnagramRemote/Tests/{f}") for f in TESTS]
w(group(APPGRP, "AnagramRemote", "AnagramRemote", appkids + [TESTGRP]))
w("\n".join(sub))
w(group(TESTGRP, "Tests", "Tests", testkids))
w(f'\t\t{MAINGRP} = {{isa = PBXGroup; children = (\n\t\t\t\t{APPGRP},\n\t\t\t\t{PRODGRP}\n\t\t\t); sourceTree = "<group>"; }};')
w(f'\t\t{PRODGRP} = {{isa = PBXGroup; children = (\n\t\t\t\t{APPPROD},\n\t\t\t\t{TESTPROD}\n\t\t\t); name = Products; sourceTree = "<group>"; }};')
w("/* End PBXGroup section */\n")

def nt(tid, name, prod, ptype, cl, srcs, fw, res, deps):
    return (f'\t\t{tid} = {{isa = PBXNativeTarget; buildConfigurationList = {cl}; buildPhases = (\n\t\t\t\t{srcs},\n\t\t\t\t{fw},\n\t\t\t\t{res}\n\t\t\t); buildRules = (); dependencies = ({deps}); name = {name}; productName = {name}; productReference = {prod}; productType = "{ptype}"; }};')
w("/* Begin PBXNativeTarget section */")
w(nt(APPT, "AnagramRemote", APPPROD, "com.apple.product-type.application", CL_A, SRC_A, FW_A, RES_A, ""))
w(nt(TESTT, "AnagramRemoteTests", TESTPROD, "com.apple.product-type.bundle.unit-test", CL_T, SRC_T, FW_T, uid("resT"), DEP))
w("/* End PBXNativeTarget section */\n")
w("/* Begin PBXProject section */")
w(f'\t\t{PROJ} = {{isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 1500; LastUpgradeCheck = 1500; }}; buildConfigurationList = {CL_P}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {MAINGRP}; productRefGroup = {PRODGRP}; projectDirPath = ""; projectRoot = ""; targets = (\n\t\t\t\t{APPT},\n\t\t\t\t{TESTT}\n\t\t\t); }};')
w("/* End PBXProject section */\n")
w("/* Begin PBXResourcesBuildPhase section */")
w(f"\t\t{RES_A} = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({bf(assets)}); runOnlyForDeploymentPostprocessing = 0; }};")
w(f"\t\t{uid('resT')} = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};")
w("/* End PBXResourcesBuildPhase section */\n")
w("/* Begin PBXSourcesBuildPhase section */")
for sid, tgt in ((SRC_A, "app"), (SRC_T, "test")):
    fl = ",".join(f"\n\t\t\t\t{bf(p)}" for p, t in files if t == tgt)
    w(f"\t\t{sid} = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({fl}\n\t\t\t); runOnlyForDeploymentPostprocessing = 0; }};")
w("/* End PBXSourcesBuildPhase section */\n")
w("/* Begin PBXTargetDependency section */")
w(f"\t\t{DEP} = {{isa = PBXTargetDependency; target = {APPT}; targetProxy = {PROXY}; }};")
w("/* End PBXTargetDependency section */\n")

common = ["ALWAYS_SEARCH_USER_PATHS = NO", "CLANG_ENABLE_MODULES = YES", "SDKROOT = iphoneos",
          "IPHONEOS_DEPLOYMENT_TARGET = 16.0", "SWIFT_VERSION = 5.0", "TARGETED_DEVICE_FAMILY = 2"]
def cfg(cid, name, extra):
    s = "".join(f"\n\t\t\t\t{x};" for x in extra)
    return f"\t\t{cid} = {{isa = XCBuildConfiguration; buildSettings = {{{s}\n\t\t\t}}; name = {name}; }};"
app = ["PRODUCT_BUNDLE_IDENTIFIER = com.reshwinnishith.anagramremote", "PRODUCT_NAME = AnagramRemote",
       "GENERATE_INFOPLIST_FILE = YES", "INFOPLIST_KEY_UILaunchScreen_Generation = YES",
       'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"',
       "INFOPLIST_KEY_UIRequiresFullScreen = YES",
       "INFOPLIST_KEY_CFBundleDisplayName = \"Anagram Remote\"",
       "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor",
       "CODE_SIGN_STYLE = Automatic", "MARKETING_VERSION = 0.1.0", "CURRENT_PROJECT_VERSION = 1",
       "SWIFT_EMIT_LOC_STRINGS = YES", 'LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks"']
test = ["PRODUCT_BUNDLE_IDENTIFIER = com.reshwinnishith.anagramremote.tests", "PRODUCT_NAME = AnagramRemoteTests",
        "GENERATE_INFOPLIST_FILE = YES", "CODE_SIGN_STYLE = Automatic",
        'TEST_HOST = "$(BUILT_PRODUCTS_DIR)/AnagramRemote.app/AnagramRemote"', 'BUNDLE_LOADER = "$(TEST_HOST)"',
        'LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @loader_path/Frameworks"']
w("/* Begin XCBuildConfiguration section */")
w(cfg(CFG["PD"], "Debug", common + ["SWIFT_OPTIMIZATION_LEVEL = \"-Onone\"", "ONLY_ACTIVE_ARCH = YES", "ENABLE_TESTABILITY = YES"]))
w(cfg(CFG["PR"], "Release", common + ["SWIFT_COMPILATION_MODE = wholemodule"]))
w(cfg(CFG["AD"], "Debug", app)); w(cfg(CFG["AR"], "Release", app))
w(cfg(CFG["TD"], "Debug", test)); w(cfg(CFG["TR"], "Release", test))
w("/* End XCBuildConfiguration section */\n")
w("/* Begin XCConfigurationList section */")
for cl, d, r in ((CL_P, "PD", "PR"), (CL_A, "AD", "AR"), (CL_T, "TD", "TR")):
    w(f"\t\t{cl} = {{isa = XCConfigurationList; buildConfigurations = (\n\t\t\t\t{CFG[d]},\n\t\t\t\t{CFG[r]}\n\t\t\t); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};")
w("/* End XCConfigurationList section */")
w(f"\t}};\n\trootObject = {PROJ};\n}}")

os.makedirs("AnagramRemote.xcodeproj", exist_ok=True)
open("AnagramRemote.xcodeproj/project.pbxproj", "w").write("\n".join(out) + "\n")

def ref(tid, prod, name, extra=""):
    return (f'<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{tid}" '
            f'BuildableName = "{prod}" BlueprintName = "{name}" ReferencedContainer = "container:AnagramRemote.xcodeproj">'
            f'</BuildableReference>')
scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1500" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            {ref(APPT, "AnagramRemote.app", "AnagramRemote")}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            {ref(TESTT, "AnagramRemoteTests.xctest", "AnagramRemoteTests")}
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {ref(APPT, "AnagramRemote.app", "AnagramRemote")}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"></AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>
</Scheme>
"""
os.makedirs("AnagramRemote.xcodeproj/xcshareddata/xcschemes", exist_ok=True)
open("AnagramRemote.xcodeproj/xcshareddata/xcschemes/AnagramRemote.xcscheme", "w").write(scheme)
print("wrote project.pbxproj and shared scheme")
