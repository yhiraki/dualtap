// OutputPath.swift — resolve the combined-track output path from the -o option.
import Foundation

// resolveOutputPath decides the final output file path.
// - No user path: default "<cwd>/dualtap-<timestamp>.<ext>".
// - User path without an extension: append ".<ext>" so a forgotten extension in
//   `-o .../20260708_180513` still yields a well-named file matching the container.
// - User path with any extension: used verbatim.
public func resolveOutputPath(userOutput: String?, timestamp: String, ext: String, cwd: String) -> String {
    guard let out = userOutput else {
        return cwd + "/dualtap-\(timestamp).\(ext)"
    }
    return (out as NSString).pathExtension.isEmpty ? out + ".\(ext)" : out
}
