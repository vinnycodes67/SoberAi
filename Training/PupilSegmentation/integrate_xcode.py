"""Registers Sober/Resources/PupilSegmentation.mlpackage in the Xcode
project (Sober.xcodeproj/project.pbxproj) as a Resources-build-phase
member of the Sober app target, so Xcode compiles it to .mlmodelc at
build time the same way it already does for the bundled fonts. Run once,
after export_coreml.py has produced the .mlpackage and it's been copied
into Sober/Resources/.

xcodegen isn't installed in this environment (confirmed in an earlier
session), so this edits the pbxproj by hand, following the exact pattern
already used for the other files in the Resources group/build phase.
"""

import re
import secrets

PBXPROJ = "../../Sober.xcodeproj/project.pbxproj"
RESOURCES_GROUP_UID = "CF199D20615C689ACDD35182"
RESOURCES_PHASE_UID = "0D6C6CF1F73AAE938B18C4F1"
MODEL_NAME = "PupilSegmentation.mlpackage"


def uid(used: set) -> str:
    while True:
        candidate = secrets.token_hex(12).upper()
        if candidate not in used:
            used.add(candidate)
            return candidate


def main():
    with open(PBXPROJ) as f:
        content = f.read()

    if MODEL_NAME in content:
        print(f"{MODEL_NAME} is already registered in the pbxproj — nothing to do.")
        return

    used = set(re.findall(r"\b[0-9A-F]{24}\b", content))
    file_ref = uid(used)
    build_file = uid(used)

    fileref_line = (
        f'\t\t{file_ref} /* {MODEL_NAME} */ = {{isa = PBXFileReference; '
        f'lastKnownFileType = folder.mlpackage; path = {MODEL_NAME}; sourceTree = "<group>"; }};\n'
    )
    content = content.replace(
        "/* End PBXFileReference section */", fileref_line + "/* End PBXFileReference section */"
    )

    buildfile_line = (
        f'\t\t{build_file} /* {MODEL_NAME} in Resources */ = '
        f"{{isa = PBXBuildFile; fileRef = {file_ref} /* {MODEL_NAME} */; }};\n"
    )
    content = content.replace(
        "/* End PBXBuildFile section */", buildfile_line + "/* End PBXBuildFile section */"
    )

    group_pattern = re.compile(
        re.escape(RESOURCES_GROUP_UID) + r" /\* Resources \*/ = \{\s*\n\s*isa = PBXGroup;\s*\n\s*children = \(\s*\n"
    )
    match = group_pattern.search(content)
    if not match:
        raise RuntimeError("Resources group not found — check RESOURCES_GROUP_UID")
    insert_at = match.end()
    content = content[:insert_at] + f"\t\t\t\t{file_ref} /* {MODEL_NAME} */,\n" + content[insert_at:]

    phase_pattern = re.compile(
        re.escape(RESOURCES_PHASE_UID)
        + r" /\* Resources \*/ = \{\s*\n\s*isa = PBXResourcesBuildPhase;\s*\n\s*buildActionMask = \d+;\s*\n\s*files = \(\s*\n"
    )
    match = phase_pattern.search(content)
    if not match:
        raise RuntimeError("Resources build phase not found — check RESOURCES_PHASE_UID")
    insert_at = match.end()
    content = (
        content[:insert_at] + f"\t\t\t\t{build_file} /* {MODEL_NAME} in Resources */,\n" + content[insert_at:]
    )

    with open(PBXPROJ, "w") as f:
        f.write(content)

    print(f"registered {MODEL_NAME}: fileRef={file_ref}, buildFile={build_file}")


if __name__ == "__main__":
    main()
