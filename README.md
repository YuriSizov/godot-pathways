# Godot Pathways

**Godot Pathways** is a plugin for the Godot engine that allows you to create roads and paths for your 3D worlds. You can map an interconnected network with curvatures and intersections, and then let the plugin intelligently apply meshes to it, stretching and deforming them as necessary. If it doesn't quite fit the geometry over the curves correctly, you can always use manual adjustments to achieve the results you want.

This plugin is still in development, so definitely expect (and please report) bugs!

## How it works

This plugin provides 3 new nodes for you to use.

`Pathways` node is the main node that combines the data from other nodes to produce the results. You can select where to output the resulting meshes. By default it will create a child node for output. Place it in your scene where you want the paths to be.

`PathwayNetwork` is a custom implementation of 3D paths and curves that allows to create a network of nodes with curves between them. Nodes can be a part of a straight path, or an intersection with up to 4 branches. Hold `Ctrl` to place a new path node, use `Shift` and drag from a path node to create smoothing handles. Place a single `PathwayNetwork` node as a child of your `Pathways` node.

`PathwayPiece` is a node that allows to define a mesh that will be used for either a straight part or an intersection. You need to select a `MeshInstance` for it to fetch a mesh resource. Intersection meshes need to be mapped on a "skeleton" for branches. You can use Y or X intersection type, with T existing but not being utilized yet. Place as many piece nodes as you want as children of your `Pathways` node. (Currently only the first node of any type is used).


## License
This project is provided under [MIT License](LICENSE).
