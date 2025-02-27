import Foundation
import IOUtils
import MesonAST
import Wrap

public class WrapBasedSubproject: Subproject {
  public let wrap: Wrap
  public let destDir: String

  public init(
    wrapName: String,
    wrap: Wrap,
    packagefiles: String,
    parent: Subproject?,
    destDir: String
  ) throws {
    self.wrap = wrap
    self.destDir = destDir
    try super.init(name: wrapName, parent: parent)
    try self.wrap.setupDirectory(path: self.destDir, packagefilesPath: packagefiles)
  }

  public override func parse(
    _ ns: TypeNamespace,
    dontCache: Set<String>,
    cache: inout [String: MesonAST.Node],
    memfiles: [String: String],
    analysisOptions: AnalysisOptions
  ) {
    let t = MesonTree(
      file: self.destDir + Path.separator + self.wrap.directoryNameAfterSetup
        + "\(Path.separator)meson.build",
      ns: ns,
      dontCache: dontCache,
      cache: &cache,
      memfiles: memfiles,
      subproject: self
    )
    t.analyzeTypes(
      ns: ns,
      dontCache: dontCache,
      cache: &cache,
      memfiles: memfiles,
      analysisOptions: analysisOptions
    )
    self.tree = t
  }

  public override func update() throws { try self.wrap.update() }

  public override var description: String {
    return "WrapSubproject(\(name),\(realpath),\(self.wrap.directoryNameAfterSetup))"
  }
}
