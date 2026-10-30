#!/usr/bin/env python3
"""Generate MossOttoKeyboard.xcodeproj (run from repo root): python3 Tools/gen_xcodeproj.py"""
import glob
import hashlib
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

APP = "MossOttoKeyboard"
EXT = "MossOttoKeyboardExt"
BUNDLE = "app.mossling.keyboard"
DEPLOY = "16.0"


def oid(*parts):
    return hashlib.md5("/".join(parts).encode()).hexdigest()[:24].upper()


# The app also compiles the keyboard's views and engine, so CI can render them (App/SnapshotRenderer.swift)
app_sources = sorted(glob.glob("App/*.swift")) + sorted(glob.glob("Keyboard/*.swift")) + sorted(glob.glob("Engine/*.swift"))
ext_sources = sorted(glob.glob("Keyboard/*.swift")) + sorted(glob.glob("Engine/*.swift"))
ext_resources = sorted(p for p in glob.glob("Keyboard/Resources/*") if not p.endswith(".DS_Store"))
# the sentence model (万象, ~400 MB) is fetched by CI (Tools/fetch_sentence_model.sh), not kept in git
if "Keyboard/Resources/sentence.gram" not in ext_resources:
    ext_resources = sorted(ext_resources + ["Keyboard/Resources/sentence.gram"])
app_resources = ["App/Assets.xcassets", "App/PrivacyInfo.xcprivacy", "Keyboard/Resources/emoji.txt"] + sorted(glob.glob("Keyboard/Resources/mosto_*.png"))

objs = {}  # id -> text


def add(i, body):
    objs[i] = body


def file_type(p):
    return {"swift": "sourcecode.swift", "plist": "text.plist.xml", "bin": "file", "xcassets": "folder.assetcatalog", "xcprivacy": "text.xml", "png": "image.png", "txt": "text", "gram": "file"}[p.rsplit(".", 1)[1]]


# File references grouped by folder
groups = {}
for p in sorted(set(app_sources + app_resources + ext_sources + ext_resources + ["Keyboard/Info.plist"])):
    d, name = os.path.split(p)
    groups.setdefault(d, []).append(p)
    add(oid("ref", p), f'{{isa = PBXFileReference; lastKnownFileType = {file_type(p)}; path = "{name}"; sourceTree = "<group>"; }}')

app_product = oid("product", APP)
ext_product = oid("product", EXT)
add(app_product, f'{{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {APP}.app; sourceTree = BUILT_PRODUCTS_DIR; }}')
add(ext_product, f'{{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = {EXT}.appex; sourceTree = BUILT_PRODUCTS_DIR; }}')

# Groups: nested Keyboard/Resources inside Keyboard
group_ids = {}
for d in ["App", "Engine", "Keyboard/Resources", "Keyboard"]:
    group_ids[d] = oid("group", d)
for d in ["App", "Engine", "Keyboard/Resources", "Keyboard"]:
    children = [oid("ref", p) for p in groups.get(d, [])]
    if d == "Keyboard":
        children.append(group_ids["Keyboard/Resources"])
    name = os.path.basename(d)
    add(group_ids[d], '{isa = PBXGroup; children = (' + "".join(c + ", " for c in children) + f'); path = "{name}"; sourceTree = "<group>"; }}')
products_group = oid("group", "Products")
add(products_group, f'{{isa = PBXGroup; children = ({app_product}, {ext_product}, ); name = Products; sourceTree = "<group>"; }}')
main_group = oid("group", "main")
add(main_group, '{isa = PBXGroup; children = (' + f'{group_ids["App"]}, {group_ids["Keyboard"]}, {group_ids["Engine"]}, {products_group}, ' + '); sourceTree = "<group>"; }')


def build_files(target, paths):
    ids = []
    for p in paths:
        i = oid("bf", target, p)
        add(i, f'{{isa = PBXBuildFile; fileRef = {oid("ref", p)}; }}')
        ids.append(i)
    return ids


def phase(kind, target, files, extra=""):
    i = oid("phase", kind, target)
    add(i, f'{{isa = {kind}; buildActionMask = 2147483647; files = (' + "".join(f + ", " for f in files) + f'); {extra}runOnlyForDeploymentPostprocessing = 0; }}')
    return i


app_src_phase = phase("PBXSourcesBuildPhase", APP, build_files(APP, app_sources))
app_fw_phase = phase("PBXFrameworksBuildPhase", APP, [])
app_res_phase = phase("PBXResourcesBuildPhase", APP, build_files(APP, app_resources))
embed_bf = oid("bf", APP, "embed")
add(embed_bf, f'{{isa = PBXBuildFile; fileRef = {ext_product}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }}')
embed_phase = phase("PBXCopyFilesBuildPhase", APP, [embed_bf], 'dstPath = ""; dstSubfolderSpec = 13; name = "Embed Foundation Extensions"; ')

ext_src_phase = phase("PBXSourcesBuildPhase", EXT, build_files(EXT, ext_sources))
ext_fw_phase = phase("PBXFrameworksBuildPhase", EXT, [])
ext_res_phase = phase("PBXResourcesBuildPhase", EXT, build_files(EXT, ext_resources))


def config_list(owner, common, debug_extra=None):
    ids = []
    for name in ["Debug", "Release"]:
        s = dict(common)
        if name == "Debug" and debug_extra:
            s.update(debug_extra)
        i = oid("config", owner, name)
        body = "".join(f'{k} = {v}; ' for k, v in sorted(s.items()))
        add(i, f'{{isa = XCBuildConfiguration; buildSettings = {{{body}}}; name = {name}; }}')
        ids.append(i)
    li = oid("configlist", owner)
    add(li, '{isa = XCConfigurationList; buildConfigurations = (' + "".join(x + ", " for x in ids) + '); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }')
    return li


project_settings = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": DEPLOY,
    "SDKROOT": "iphoneos",
    "SWIFT_VERSION": "5.0",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "SWIFT_OPTIMIZATION_LEVEL": '"-O"',
    "COPY_PHASE_STRIP": "NO",
    # the decoder's hot loops: no runtime exclusivity checks in release (still checked at compile time and in debug;
    # 九宫格 全拼 sentence decodes measured 75 → 53 ms)
    "OTHER_SWIFT_FLAGS": '"-enforce-exclusivity=unchecked"',
}
project_debug = {"SWIFT_OPTIMIZATION_LEVEL": '"-Onone"', "OTHER_SWIFT_FLAGS": '""', "SWIFT_COMPILATION_MODE": "singlefile",
                 "ONLY_ACTIVE_ARCH": "YES", "DEBUG_INFORMATION_FORMAT": "dwarf",
                 "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG"}
common_target = {
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "MARKETING_VERSION": "1.0",
    "GENERATE_INFOPLIST_FILE": "YES",
    "TARGETED_DEVICE_FAMILY": "1",
    "DEVELOPMENT_TEAM": '""',
    "INFOPLIST_KEY_CFBundleDisplayName": '"Mosto键盘"',
}
app_settings = dict(common_target, **{
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE,
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": '"UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"',
    "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption": "NO",
    "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks", )',
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
})
ext_settings = dict(common_target, **{
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE + ".ext",
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "INFOPLIST_FILE": "Keyboard/Info.plist",
    "SKIP_INSTALL": "YES",
    "APPLICATION_EXTENSION_API_ONLY": "YES",
    "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks", )',
})

ext_target = oid("target", EXT)
app_target = oid("target", APP)
proxy = oid("proxy", EXT)
dep = oid("dep", EXT)
project = oid("project")
add(proxy, f'{{isa = PBXContainerItemProxy; containerPortal = {project}; proxyType = 1; remoteGlobalIDString = {ext_target}; remoteInfo = {EXT}; }}')
add(dep, f'{{isa = PBXTargetDependency; target = {ext_target}; targetProxy = {proxy}; }}')

add(ext_target, f'{{isa = PBXNativeTarget; buildConfigurationList = {config_list(EXT, ext_settings)}; buildPhases = ({ext_src_phase}, {ext_fw_phase}, {ext_res_phase}, ); buildRules = (); dependencies = (); name = {EXT}; productName = {EXT}; productReference = {ext_product}; productType = "com.apple.product-type.app-extension"; }}')
add(app_target, f'{{isa = PBXNativeTarget; buildConfigurationList = {config_list(APP, app_settings)}; buildPhases = ({app_src_phase}, {app_fw_phase}, {app_res_phase}, {embed_phase}, ); buildRules = (); dependencies = ({dep}, ); name = {APP}; productName = {APP}; productReference = {app_product}; productType = "com.apple.product-type.application"; }}')
add(project, f'{{isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 1500; LastUpgradeCheck = 1500; }}; buildConfigurationList = {config_list("project", project_settings, project_debug)}; compatibilityVersion = "Xcode 14.0"; developmentRegion = "zh-Hans"; hasScannedForEncodings = 0; knownRegions = (en, Base, "zh-Hans", ); mainGroup = {main_group}; productRefGroup = {products_group}; projectDirPath = ""; projectRoot = ""; targets = ({app_target}, {ext_target}, ); }}')

out = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};", "\tobjectVersion = 56;", "\tobjects = {"]
for k in sorted(objs):
    out.append(f"\t\t{k} = {objs[k]};")
out += ["\t};", f"\trootObject = {project};", "}", ""]

os.makedirs(f"{APP}.xcodeproj", exist_ok=True)
with open(f"{APP}.xcodeproj/project.pbxproj", "w", encoding="utf-8") as f:
    f.write("\n".join(out))
print(f"wrote {APP}.xcodeproj ({len(objs)} objects, {len(app_sources)} app + {len(ext_sources)} keyboard sources)")

# Shared scheme so xcodebuild (CI) can build/archive without opening Xcode
scheme_dir = f"{APP}.xcodeproj/xcshareddata/xcschemes"
os.makedirs(scheme_dir, exist_ok=True)


def ref(target_id, name, product):
    return (f'<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{target_id}" '
            f'BuildableName = "{product}" BlueprintName = "{name}" ReferencedContainer = "container:{APP}.xcodeproj"></BuildableReference>')


app_ref = ref(app_target, APP, APP + ".app")
ext_ref = ref(ext_target, EXT, EXT + ".appex")
scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1500" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            {app_ref}
         </BuildActionEntry>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            {ext_ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {app_ref}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
with open(f"{scheme_dir}/{APP}.xcscheme", "w", encoding="utf-8") as f:
    f.write(scheme)
