# BehBeh Trees
A flavor of Behavior Trees for Godot 4 featuring a GraphEdit-based editor.

![screenshot of BehBeh Trees](doc/Screenshot_2023-05-26_173006.png)

## Why?
I like being able to edit and author trees visually. I couldn't find a Behavior Tree solution for Godot 4 that used GraphEdit.

## TLDR
- BehTrees contain BehNodes. Both are Resources.
- tick() BehTrees.
  - `fn tick(dt: float, bb: Dictionary) -> BehConst.Status`
  - It takes a delta-time "dt" and arbitrary-purpose blackboard "bb". Returns Busy, Resolved, or Failed.
  - e.g.: Call tick() in a Node's _process.
- To create custom behavior, define your own BehNode implementations. BehNode is a _Resource_ type. **New BehNodes MUST be `@tool`!**
  - There are a handful of useful built-in impls, and a template txt for new BehNodes in the addon folder.
  - **New BehNodes MUST be `@tool`!** This is due to editor limitations and the decision to reduce boilerplate, `BehNode` features overrideable methods to define how it looks in the BehTree Editor.

### Version 1.0 possibly-surprising limitations:
  - **Do not share tree references across multiple Node runners** and expect sensible behavior.
	- `bb` is supposed to be the sole source of state, but this is not true in reality currently, due to Select / Sequence node impls.
  - Performance has NOT been evaluated. Production use is currently just beginning. 1.0 indicates the tool has been stable through testing, but in-game performance is still to be determined, and the current intended use is for smaller projects that are unlikely to encounter performance issues.
  - After defining a new BehNode @tool, you likely need to Reload the project (Project -> Reload Current Project) to avoid issues with the add-node resource picker.

## Using the Editor
- Inspect a BehTree to open the BehTree Editor in the bottom dock.
- Right-click on the graph to add a new BehNode.
- Double-click a BehNode in a BehTree to inspect it and edit any @exported variables.
- Customize your BehNodes' editor appearances by overriding `editor_` methods defined in BehNode (see: `tree/beh_node.gd`).

## Useful meta-nodes
- `Sequence`: Supports N children, ticking one at a time, in order. Once a child is ticked, the sequence waits until re-ticking (this behavior might change in a major version revision).
- `Set`: Supports N children, ticking all of them each tick().
- `Select`: Supports N children. Ticks children in order until one of them returns Resolved or Busy. A Busy child is re-ticked on the next call.
- `Select Random`: Supports N children. Randomly ticks one of its children. If a child returns Busy, that child is re-ticked on the next call.
- `Condition`: Supports up to 2 children. The first child is ticked if the condition returns true, otherwise the second child is ticked, if it exists. This behavior can be inverted.

### Selectors re-tick Busy children ("stickiness")
Select, Select Random, and Condition exhibit "sticky" child-ticking behaviors. When a child returns Busy, it gets ticked again when the parent selector gets its next tick(), ignoring its original selector condition as long as that child is still Busy. Some selectors can disable this behavior as an inspector option (a mode referred to as "rude").

### Be careful implementing new nodes that can have children.
A base class `BehNodeXMultiChildren` is used by nodes that can have children. Sequence and Condition are good examples of correct implemenations. In particular:
- `get_can_add_child()` must always return true or always return false. To limit adding children _only sometimes_, return false in `try_add_child()` instead.
- `get_children()` must return the mutable backing array containing a BehNode's children. This allows the editor to sort those children according to editor node positions.

Incorrectly implementing node children can break the tree. Fun!

### Debug logging
VERY verbose, but useful, log printing can be enabled in `beh_editor.gd`.`dprintd(s: String)`. (What can I say; Godot's editor tool debugging support is somewhat lackluster).
  
## License

Dual-licensed under MIT & Apache 2.0.

## Alternatives
- Consider [beehave](https://github.com/bitbrain/beehave), which offers `Node`-based (rather than `Resource`+Editor-based) behavior trees.


<3

