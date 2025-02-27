public final class Method: Function {
  public var parent: Type

  init(name: String, parent: Type, returnTypes: [Type] = [], args: [Argument] = []) {
    self.parent = parent
    super.init(name: name, returnTypes: returnTypes, args: args)
  }
  public override func id() -> String { return self.parent.name + "." + self.name }

  public override func hash(into hasher: inout Hasher) {
    hasher.combine("method" + self.name + self.id())
  }
}
