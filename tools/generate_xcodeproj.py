#!/usr/bin/env python3
"""Writes Twelve.xcodeproj/project.pbxproj.

The project uses Xcode's folder-synchronised groups, so adding a Swift file to
Twelve/, Shared/, TwelveWidgets/ or TwelveTests/ needs no project edit. Run
this script only if targets or build settings change:  python3 tools/generate_xcodeproj.py
"""
import os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_n = 0
# Stable ids, derived from a counter so the file is identical on every run.
def uid(tag):
    global _n; _n += 1
    return f"7E12{_n:04X}0000000000002027"[:24]

ids = {k: uid(k) for k in """project mainGroup productsGroup gApp gShared gWidgets gTests
pApp pWidgets pTests tApp tWidgets tTests
appSources appFrameworks appResources appEmbed widSources widFrameworks widResources testSources testFrameworks testResources
bfAppCore bfWidCore bfTestCore bfEmbed
depAppCore depWidCore depTestCore pkgCore
proxyWid tdWid proxyApp tdApp
clProject clApp clWid clTest
cProjD cProjR cAppD cAppR cWidD cWidR cTestD cTestR""".split()}
I = ids

def settings(d, indent="\t\t\t\t"):
    out = []
    for k in sorted(d):
        v = d[k]
        if isinstance(v, list):
            out.append(f"{indent}{k} = (\n" + "".join(f"{indent}\t\"{x}\",\n" for x in v) + f"{indent});")
        else:
            out.append(f'{indent}{k} = "{v}";')
    return "\n".join(out)

def config(key, name, d):
    return f"""\t\t{I[key]} /* {name} */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{settings(d)}
\t\t\t}};
\t\t\tname = {name};
\t\t}};"""

common = {
    "ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20", "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES", "GCC_NO_COMMON_BLOCKS": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": "26.0", "SDKROOT": "iphoneos", "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1", "MARKETING_VERSION": "1.0", "CURRENT_PROJECT_VERSION": "1",
    "CODE_SIGN_STYLE": "Automatic", "DEVELOPMENT_TEAM": "", "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "CLANG_WARN_BOOL_CONVERSION": "YES", "CLANG_WARN_EMPTY_BODY": "YES", "CLANG_WARN_INFINITE_RECURSION": "YES",
    "CLANG_WARN_UNREACHABLE_CODE": "YES", "GCC_WARN_UNUSED_VARIABLE": "YES", "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES", "MTL_FAST_MATH": "YES",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
}
debug = dict(common, **{"DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES", "GCC_DYNAMIC_NO_PIC": "NO",
    "GCC_OPTIMIZATION_LEVEL": "0", "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"], "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)", "SWIFT_OPTIMIZATION_LEVEL": "-Onone", "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE"})
release = dict(common, **{"DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym", "ENABLE_NS_ASSERTIONS": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule", "VALIDATE_PRODUCT": "YES", "MTL_ENABLE_DEBUG_INFO": "NO"})

app = {
    "PRODUCT_BUNDLE_IDENTIFIER": "com.twelve.app", "PRODUCT_NAME": "$(TARGET_NAME)",
    "INFOPLIST_FILE": "Config/Twelve-Info.plist", "GENERATE_INFOPLIST_FILE": "YES",
    "CODE_SIGN_ENTITLEMENTS": "Config/Twelve.entitlements",
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "INFOPLIST_KEY_CFBundleDisplayName": "TWELVE", "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.lifestyle",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES", "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait",
    "INFOPLIST_KEY_NSSupportsLiveActivities": "YES",
    "INFOPLIST_KEY_NSCameraUsageDescription": "TWELVE uses the camera only when you choose to take a photo for a challenge. Photos stay on this iPhone.",
    "INFOPLIST_KEY_NSHealthShareUsageDescription": "If you choose to connect Health, TWELVE reads your walking workouts so they can count toward the walking challenge. Nothing else is read.",
    "INFOPLIST_KEY_NSHealthUpdateUsageDescription": "TWELVE does not write to Health.",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "ENABLE_PREVIEWS": "YES",
}
wid = {
    "PRODUCT_BUNDLE_IDENTIFIER": "com.twelve.app.widgets", "PRODUCT_NAME": "$(TARGET_NAME)",
    "INFOPLIST_FILE": "Config/TwelveWidgets-Info.plist", "GENERATE_INFOPLIST_FILE": "YES",
    "CODE_SIGN_ENTITLEMENTS": "Config/TwelveWidgets.entitlements",
    "INFOPLIST_KEY_CFBundleDisplayName": "TWELVE", "SKIP_INSTALL": "YES", "APPLICATION_EXTENSION_API_ONLY": "YES",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"],
}
test = {
    "PRODUCT_BUNDLE_IDENTIFIER": "com.twelve.app.tests", "PRODUCT_NAME": "$(TARGET_NAME)", "GENERATE_INFOPLIST_FILE": "YES",
    "BUNDLE_LOADER": "$(TEST_HOST)", "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Twelve.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Twelve",
}

def sync(key, path):
    return f'\t\t{I[key]} /* {path} */ = {{isa = PBXFileSystemSynchronizedRootGroup; explicitFileTypes = {{}}; explicitFolders = (); path = {path}; sourceTree = "<group>"; }};'

def phase(key, isa, files=()):
    body = "".join(f"\t\t\t\t{f},\n" for f in files)
    return f"""\t\t{I[key]} = {{
\t\t\tisa = {isa};
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{body}\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};"""

def target(key, name, cl, phases, deps, groups, pkg, product, ptype):
    return f"""\t\t{I[key]} /* {name} */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {I[cl]};
\t\t\tbuildPhases = (
{"".join(f"{chr(9)*4}{I[p]},{chr(10)}" for p in phases)}\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
{"".join(f"{chr(9)*4}{I[d]},{chr(10)}" for d in deps)}\t\t\t);
\t\t\tfileSystemSynchronizedGroups = (
{"".join(f"{chr(9)*4}{I[g]},{chr(10)}" for g in groups)}\t\t\t);
\t\t\tname = {name};
\t\t\tpackageProductDependencies = (
\t\t\t\t{I[pkg]},
\t\t\t);
\t\t\tproductName = {name};
\t\t\tproductReference = {I[product]};
\t\t\tproductType = "{ptype}";
\t\t}};"""

def clist(key, a, b):
    return f"""\t\t{I[key]} = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{I[a]},
\t\t\t\t{I[b]},
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};"""

out = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 77;
\tobjects = {{

/* Begin PBXBuildFile section */
\t\t{I['bfAppCore']} /* TwelveCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {I['depAppCore']}; }};
\t\t{I['bfWidCore']} /* TwelveCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {I['depWidCore']}; }};
\t\t{I['bfTestCore']} /* TwelveCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {I['depTestCore']}; }};
\t\t{I['bfEmbed']} /* TwelveWidgets.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {I['pWidgets']}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
\t\t{I['proxyWid']} = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {I['project']};
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {I['tWidgets']};
\t\t\tremoteInfo = TwelveWidgets;
\t\t}};
\t\t{I['proxyApp']} = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {I['project']};
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {I['tApp']};
\t\t\tremoteInfo = Twelve;
\t\t}};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
\t\t{I['appEmbed']} /* Embed Foundation Extensions */ = {{
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "";
\t\t\tdstSubfolderSpec = 13;
\t\t\tfiles = (
\t\t\t\t{I['bfEmbed']},
\t\t\t);
\t\t\tname = "Embed Foundation Extensions";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
\t\t{I['pApp']} /* Twelve.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Twelve.app; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{I['pWidgets']} /* TwelveWidgets.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = TwelveWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{I['pTests']} /* TwelveTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = TwelveTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
{sync('gApp', 'Twelve')}
{sync('gShared', 'Shared')}
{sync('gWidgets', 'TwelveWidgets')}
{sync('gTests', 'TwelveTests')}
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
{phase('appFrameworks', 'PBXFrameworksBuildPhase', [I['bfAppCore']])}
{phase('widFrameworks', 'PBXFrameworksBuildPhase', [I['bfWidCore']])}
{phase('testFrameworks', 'PBXFrameworksBuildPhase', [I['bfTestCore']])}
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{I['mainGroup']} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{I['gApp']} /* Twelve */,
\t\t\t\t{I['gShared']} /* Shared */,
\t\t\t\t{I['gWidgets']} /* TwelveWidgets */,
\t\t\t\t{I['gTests']} /* TwelveTests */,
\t\t\t\t{I['productsGroup']} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{I['productsGroup']} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{I['pApp']} /* Twelve.app */,
\t\t\t\t{I['pWidgets']} /* TwelveWidgets.appex */,
\t\t\t\t{I['pTests']} /* TwelveTests.xctest */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
{target('tApp', 'Twelve', 'clApp', ['appSources', 'appFrameworks', 'appResources', 'appEmbed'], ['tdWid'], ['gApp', 'gShared'], 'depAppCore', 'pApp', 'com.apple.product-type.application')}
{target('tWidgets', 'TwelveWidgets', 'clWid', ['widSources', 'widFrameworks', 'widResources'], [], ['gWidgets', 'gShared'], 'depWidCore', 'pWidgets', 'com.apple.product-type.app-extension')}
{target('tTests', 'TwelveTests', 'clTest', ['testSources', 'testFrameworks', 'testResources'], ['tdApp'], ['gTests'], 'depTestCore', 'pTests', 'com.apple.product-type.bundle.unit-test')}
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{I['project']} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 2600;
\t\t\t\tLastUpgradeCheck = 2600;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{I['tApp']} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;
\t\t\t\t\t}};
\t\t\t\t\t{I['tWidgets']} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;
\t\t\t\t\t}};
\t\t\t\t\t{I['tTests']} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;
\t\t\t\t\t\tTestTargetID = {I['tApp']};
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {I['clProject']};
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {I['mainGroup']};
\t\t\tminimizedProjectReferenceProxies = 1;
\t\t\tpackageReferences = (
\t\t\t\t{I['pkgCore']} /* XCLocalSwiftPackageReference "Packages/TwelveCore" */,
\t\t\t);
\t\t\tpreferredProjectObjectVersion = 77;
\t\t\tproductRefGroup = {I['productsGroup']} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{I['tApp']} /* Twelve */,
\t\t\t\t{I['tWidgets']} /* TwelveWidgets */,
\t\t\t\t{I['tTests']} /* TwelveTests */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
{phase('appResources', 'PBXResourcesBuildPhase')}
{phase('widResources', 'PBXResourcesBuildPhase')}
{phase('testResources', 'PBXResourcesBuildPhase')}
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
{phase('appSources', 'PBXSourcesBuildPhase')}
{phase('widSources', 'PBXSourcesBuildPhase')}
{phase('testSources', 'PBXSourcesBuildPhase')}
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
\t\t{I['tdWid']} = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = {I['tWidgets']};
\t\t\ttargetProxy = {I['proxyWid']};
\t\t}};
\t\t{I['tdApp']} = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = {I['tApp']};
\t\t\ttargetProxy = {I['proxyApp']};
\t\t}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
{config('cProjD', 'Debug', debug)}
{config('cProjR', 'Release', release)}
{config('cAppD', 'Debug', app)}
{config('cAppR', 'Release', app)}
{config('cWidD', 'Debug', wid)}
{config('cWidR', 'Release', wid)}
{config('cTestD', 'Debug', test)}
{config('cTestR', 'Release', test)}
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
{clist('clProject', 'cProjD', 'cProjR')}
{clist('clApp', 'cAppD', 'cAppR')}
{clist('clWid', 'cWidD', 'cWidR')}
{clist('clTest', 'cTestD', 'cTestR')}
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
\t\t{I['pkgCore']} /* XCLocalSwiftPackageReference "Packages/TwelveCore" */ = {{
\t\t\tisa = XCLocalSwiftPackageReference;
\t\t\trelativePath = Packages/TwelveCore;
\t\t}};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
\t\t{I['depAppCore']} /* TwelveCore */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tproductName = TwelveCore;
\t\t}};
\t\t{I['depWidCore']} /* TwelveCore */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tproductName = TwelveCore;
\t\t}};
\t\t{I['depTestCore']} /* TwelveCore */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tproductName = TwelveCore;
\t\t}};
/* End XCSwiftPackageProductDependency section */
\t}};
\trootObject = {I['project']} /* Project object */;
}}
"""
with open(os.path.join(ROOT, "Twelve.xcodeproj/project.pbxproj"), "w") as f:
    f.write(out)

scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{I['tApp']}" BuildableName = "Twelve.app" BlueprintName = "Twelve" ReferencedContainer = "container:Twelve.xcodeproj"></BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES" shouldAutocreateTestPlan = "YES">
      <Testables>
         <TestableReference skipped = "NO" parallelizable = "NO">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{I['tTests']}" BuildableName = "TwelveTests.xctest" BlueprintName = "TwelveTests" ReferencedContainer = "container:Twelve.xcodeproj"></BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{I['tApp']}" BuildableName = "Twelve.app" BlueprintName = "Twelve" ReferencedContainer = "container:Twelve.xcodeproj"></BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{I['tApp']}" BuildableName = "Twelve.app" BlueprintName = "Twelve" ReferencedContainer = "container:Twelve.xcodeproj"></BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"></AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>
</Scheme>
"""
with open(os.path.join(ROOT, "Twelve.xcodeproj/xcshareddata/xcschemes/Twelve.xcscheme"), "w") as f:
    f.write(scheme)
with open(os.path.join(ROOT, "Twelve.xcodeproj/project.xcworkspace/contents.xcworkspacedata"), "w") as f:
    f.write('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version = "1.0">\n   <FileRef location = "self:"></FileRef>\n</Workspace>\n')
print("project written")
