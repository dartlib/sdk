// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// This library contains utilities for reading and analyzing snapshot profiles
/// produced by `--write-v8-snapshot-profile-to` VM flag.
library vm.snapshot.v8_profile;

import 'package:meta/meta.dart';
import 'package:vm/snapshot/name.dart';

import 'package:vm/snapshot/program_info.dart';

/// This class represents snapshot graph.
///
/// Note that we do not eagerly deserialize the graph, instead we provide helper
/// methods and wrapper objects to work with serialized representation.
class Snapshot {
  final Meta meta;
  final int nodeCount;
  final int edgeCount;

  /// Serialized flat representation of nodes in the graph. Each node occupies
  /// [meta.nodeFieldCount] consecutive elements of the list.
  final List _nodes;

  /// Serialized flat representation of edges between nodes. Each edge occupies
  /// [meta.edgeFieldCount] consecutive elements of the list. All outgoing edges
  /// for a node are serialized consecutively, number of outgoing edges is given
  /// by the value at index [meta.nodeEdgeCountIndex] inside the node.
  final List _edges;

  /// Auxiliary array which gives starting index of edges (in the [_edges] list)
  /// for the given node index.
  final List<int> _edgesStartIndexForNode;

  final List strings;

  Snapshot._(this.meta, this.nodeCount, this.edgeCount, this._nodes,
      this._edges, this.strings, this._edgesStartIndexForNode);

  /// Return node with the given index.
  Node nodeAt(int index) {
    assert(index >= 0, 'Node index should be positive: $index');
    return Node._(snapshot: this, index: index);
  }

  /// Return all nodes in the snapshot.
  Iterable<Node> get nodes => Iterable.generate(nodeCount, nodeAt);

  /// Returns true if the given JSON object is likely to be a serialized
  /// snapshot using V8 heap snapshot format.
  static bool isV8HeapSnapshot(Object m) =>
      m is Map<String, dynamic> && m.containsKey('snapshot');

  /// Construct [Snapshot] object from the given JSON object.
  factory Snapshot.fromJson(Map<String, dynamic> m) {
    // Extract meta information first.
    final meta = Meta._fromJson(m['snapshot']['meta']);

    final nodes = m['nodes'];

    // Build an array of starting indexes of edges for each node.
    final edgesStartIndexForNode = <int>[0];
    int nextStartIndex = 0;
    for (var i = meta.nodeEdgeCountIndex;
        i < nodes.length;
        i += meta.nodeFieldCount) {
      nextStartIndex += nodes[i];
      edgesStartIndexForNode.add(nextStartIndex);
    }

    return Snapshot._(
        meta,
        m['snapshot']['node_count'],
        m['snapshot']['edge_count'],
        m['nodes'],
        m['edges'],
        m['strings'],
        edgesStartIndexForNode);
  }
}

/// Meta-information about the serialized snapshot.
///
/// Describes the structure of serialized nodes and edges by giving indexes of
/// the various fields.
class Meta {
  final int nodeTypeIndex;
  final int nodeNameIndex;
  final int nodeIdIndex;
  final int nodeSelfSizeIndex;
  final int nodeEdgeCountIndex;
  final int nodeFieldCount;

  final int edgeTypeIndex;
  final int edgeNameOrIndexIndex;
  final int edgeToNodeIndex;
  final int edgeFieldCount;

  final List<String> nodeTypes;
  final List<String> edgeTypes;

  Meta._(
      {this.nodeTypeIndex,
      this.nodeNameIndex,
      this.nodeIdIndex,
      this.nodeSelfSizeIndex,
      this.nodeEdgeCountIndex,
      this.nodeFieldCount,
      this.edgeTypeIndex,
      this.edgeNameOrIndexIndex,
      this.edgeToNodeIndex,
      this.edgeFieldCount,
      this.nodeTypes,
      this.edgeTypes});

  factory Meta._fromJson(Map<String, dynamic> m) {
    final nodeFields = m['node_fields'];
    final nodeTypes = m['node_types'].first.cast<String>();
    final edgeFields = m['edge_fields'];
    final edgeTypes = m['edge_types'].first.cast<String>();
    return Meta._(
        nodeTypeIndex: nodeFields.indexOf('type'),
        nodeNameIndex: nodeFields.indexOf('name'),
        nodeIdIndex: nodeFields.indexOf('id'),
        nodeSelfSizeIndex: nodeFields.indexOf('self_size'),
        nodeEdgeCountIndex: nodeFields.indexOf('edge_count'),
        nodeFieldCount: nodeFields.length,
        edgeTypeIndex: edgeFields.indexOf('type'),
        edgeNameOrIndexIndex: edgeFields.indexOf('name_or_index'),
        edgeToNodeIndex: edgeFields.indexOf('to_node'),
        edgeFieldCount: edgeFields.length,
        nodeTypes: nodeTypes,
        edgeTypes: edgeTypes);
  }
}

/// Edge from [Node] to [Node] in the [Snapshot] graph.
class Edge {
  final Snapshot snapshot;

  /// Index of this [Edge] within the [snapshot].
  final int index;

  Edge._({this.snapshot, this.index});

  String get type => snapshot
      .meta.edgeTypes[snapshot._edges[_offset + snapshot.meta.edgeTypeIndex]];

  Node get target {
    return Node._(
        snapshot: snapshot,
        index: snapshot._edges[_offset + snapshot.meta.edgeToNodeIndex] ~/
            snapshot.meta.nodeFieldCount);
  }

  String get name {
    final nameOrIndex =
        snapshot._edges[_offset + snapshot.meta.edgeNameOrIndexIndex];
    return type == 'property' ? snapshot.strings[nameOrIndex] : '@$nameOrIndex';
  }

  @override
  String toString() {
    final nameOrIndex =
        snapshot._edges[_offset + snapshot.meta.edgeNameOrIndexIndex];
    return {
      'type': type,
      'nameOrIndex':
          type == 'property' ? snapshot.strings[nameOrIndex] : nameOrIndex,
      'toNode': target.index,
    }.toString();
  }

  /// Offset into [Snapshot._edges] list at which this edge begins.
  int get _offset => index * snapshot.meta.edgeFieldCount;
}

/// Node in the [Snapshot] graph.
class Node {
  final Snapshot snapshot;

  /// Index of this [Node] within the [snapshot].
  final int index;

  Node._({this.snapshot, this.index});

  int get edgeCount =>
      snapshot._nodes[_offset + snapshot.meta.nodeEdgeCountIndex];

  String get type => snapshot
      .meta.nodeTypes[snapshot._nodes[_offset + snapshot.meta.nodeTypeIndex]];

  String get name =>
      snapshot.strings[snapshot._nodes[_offset + snapshot.meta.nodeNameIndex]];

  int get selfSize =>
      snapshot._nodes[_offset + snapshot.meta.nodeSelfSizeIndex];

  int get id => snapshot._nodes[_offset + snapshot.meta.nodeIdIndex];

  /// Returns all outgoing edges for this node.
  Iterable<Edge> get edges sync* {
    var firstEdgeIndex = snapshot._edgesStartIndexForNode[index];
    for (var i = 0, n = edgeCount; i < n; i++) {
      yield Edge._(snapshot: snapshot, index: firstEdgeIndex + i);
    }
  }

  @override
  String toString() {
    return {
      'type': type,
      'name': name,
      'id': id,
      'selfSize': selfSize,
      'edges': edges.toList(),
    }.toString();
  }

  /// Returns the target of an outgoing edge with the given name (if any).
  Node operator [](String edgeName) => this
      .edges
      .firstWhere((e) => e.name == edgeName, orElse: () => null)
      ?.target;

  @override
  bool operator ==(Object other) {
    return other is Node && other.index == index;
  }

  @override
  int get hashCode => this.index.hashCode;

  /// Offset into [Snapshot._nodes] list at which this node begins.
  int get _offset => index * snapshot.meta.nodeFieldCount;
}

/// Class representing information about V8 snapshot profile in relation
/// to a [ProgramInfo] structure that was derived from it.
class SnapshotInfo {
  final Snapshot snapshot;

  final List<ProgramInfoNode> _infoNodes;
  final Map<int, int> _ownerOf;

  SnapshotInfo._(this.snapshot, this._infoNodes, this._ownerOf);

  ProgramInfoNode ownerOf(Node node) =>
      _infoNodes[_ownerOf[node.index] ?? ProgramInfo.unknownId];
}

ProgramInfo toProgramInfo(Snapshot snap,
    {bool collapseAnonymousClosures = false}) {
  return _ProgramInfoBuilder(
          collapseAnonymousClosures: collapseAnonymousClosures)
      .build(snap);
}

class _ProgramInfoBuilder {
  final bool collapseAnonymousClosures;

  final program = ProgramInfo();

  final List<ProgramInfoNode> infoNodes = [];

  /// Mapping between snapshot [Node] index and id of [ProgramInfoNode] which
  /// own this node.
  final Map<int, int> ownerOf = {};

  /// Mapping between snapshot [Node] indices and corresponding
  /// [ProgramInfoNode] objects. Note that multiple snapshot nodes might be
  /// mapped to a single [ProgramInfoNode] (e.g. when anonymous closures are
  /// collapsed).
  final Map<int, ProgramInfoNode> infoNodeByIndex = {};

  // Mapping between package names and corresponding [ProgramInfoNode] objects
  // representing those packages.
  final Map<String, ProgramInfoNode> infoNodeForPackage = {};

  /// Owners of some [Node] are determined by the program structure and not
  /// by their reachability through the graph. For example, an owner of a
  /// function is a class that contains it, even though the function can
  /// also be reachable from another function through object pool.
  final Set<int> nodesWithFrozenOwner = {};

  /// Cache used to optimize common ancestor operation on [ProgramInfoNode] ids.
  /// See [findCommonAncestor] method.
  final Map<int, int> commonAncestorCache = {};

  _ProgramInfoBuilder({this.collapseAnonymousClosures});

  /// Recover [ProgramInfo] structure from the snapshot profile.
  ///
  /// This is done via a simple graph traversal: first all nodes representing
  /// objects with clear ownership (like libraries, classes, functions) are
  /// discovered and corresponding [ProgramInfoNode] objects are created for
  /// them. Then the rest of the snapshot is attributed to one of these nodes
  /// based on reachability (ignoring reachability from normal snapshot roots):
  /// let `R(n)` be a set of [ProgramInfoNode] objects from which a given
  /// snapshot node `n` is reachable. Then we define an owner of `n` to be
  /// a lowest common ancestor of all nodes in `R(n)`.
  ///
  /// Nodes which are not reachable from any normal [ProgramInfoNode] are
  /// attributed to special `@unknown` [ProgramInfoNode].
  ProgramInfo build(Snapshot snap) {
    infoNodes.add(program.root);
    infoNodes.add(program.stubs);
    infoNodes.add(program.unknown);

    // Create ProgramInfoNode for every snapshot node representing an element
    // of the program structure (e.g. a library, a class, a function).
    snap.nodes.forEach(getInfoNodeFor);

    // Propagate the ownership information across the edges.
    final worklist = ownerOf.keys.toList();
    while (worklist.isNotEmpty) {
      final node = snap.nodeAt(worklist.removeLast());
      final sourceOwner = ownerOf[node.index];
      for (var e in node.edges) {
        final target = e.target;
        if (!nodesWithFrozenOwner.contains(target.index)) {
          final targetOwner = ownerOf[target.index];
          final updatedOwner = findCommonAncestor(sourceOwner, targetOwner);
          if (updatedOwner != targetOwner) {
            ownerOf[target.index] = updatedOwner;
            worklist.add(target.index);
          }
        }
      }
    }

    // Now attribute sizes from the snapshot to nodes that own them.
    for (var node in snap.nodes) {
      if (node.selfSize > 0) {
        final owner = infoNodes[ownerOf[node.index] ?? ProgramInfo.unknownId];
        owner.size = (owner.size ?? 0) + node.selfSize;
      }
    }

    program.snapshotInfo = SnapshotInfo._(snap, infoNodes, ownerOf);

    return program;
  }

  ProgramInfoNode getInfoNodeFor(Node node) {
    var info = infoNodeByIndex[node.index];
    if (info == null) {
      info = createInfoNodeFor(node);
      if (info != null) {
        // Snapshot nodes which represent the program structure can't change
        // their owner during iteration - their owner is frozen and is given
        // by the program structure.
        nodesWithFrozenOwner.add(node.index);
        ownerOf[node.index] = info.parent?.id ?? info.id;

        // Handle some nodes specially.
        switch (node.type) {
          case 'Code':
            // Freeze ownership of the Instructions object.
            final instructions = node['<instructions>'];
            nodesWithFrozenOwner.add(instructions.index);
            ownerOf[instructions.index] =
                findCommonAncestor(ownerOf[instructions.index], info.id);
            break;
          case 'Library':
            // Freeze ownership of the Script objects owned by this library.
            final scripts = node['owned_scripts_'];
            if (scripts != null) {
              for (var e in scripts.edges) {
                if (e.target.type == 'Script') {
                  nodesWithFrozenOwner.add(e.target.index);
                  ownerOf[e.target.index] =
                      findCommonAncestor(ownerOf[e.target.index], info.id);
                }
              }
            }
            break;
        }
      }
    }
    return info;
  }

  ProgramInfoNode createInfoNodeFor(Node node) {
    switch (node.type) {
      case 'Code':
        var owner = node['owner_'];
        if (owner.type != 'Type') {
          if (owner.type == 'WeakSerializationReference') {
            owner = node[':owner_'];
          }
          final ownerNode =
              owner.type == 'Null' ? program.stubs : getInfoNodeFor(owner);
          return makeInfoNode(node.index,
              name: node.name, parent: ownerNode, type: NodeType.other);
        }
        break;

      case 'Function':
        if (node.name != '<anonymous signature>') {
          var owner = node['owner_'];
          if (node['data_'].type == 'ClosureData') {
            owner = node['data_']['parent_function_'];
          }
          return makeInfoNode(node.index,
              name: node.name,
              parent: getInfoNodeFor(owner),
              type: NodeType.functionNode);
        }
        break;

      case 'PatchClass':
        return getInfoNodeFor(node['patched_class_']);

      case 'Class':
        if (node['library_'] != null) {
          return makeInfoNode(node.index,
              name: node.name,
              parent: getInfoNodeFor(node['library_']) ?? program.root,
              type: NodeType.classNode);
        }
        break;

      case 'Library':
        // Create fake owner node for the package which contains this library.
        final packageName = packageOf(node.name);
        return makeInfoNode(node.index,
            name: node.name,
            parent: packageName != node.name
                ? packageOwner(packageName)
                : program.root,
            type: NodeType.libraryNode);

      case 'Field':
        return makeInfoNode(node.index,
            name: node.name,
            parent: getInfoNodeFor(node['owner_']),
            type: NodeType.other);
    }
    return null;
  }

  ProgramInfoNode makeInfoNode(int index,
      {@required ProgramInfoNode parent,
      @required String name,
      @required NodeType type}) {
    assert(parent != null,
        'Trying to create node of type ${type} with ${name} and no parent.');
    assert(name != null);

    name = Name(name).scrubbed;
    if (collapseAnonymousClosures) {
      name = Name.collapse(name);
    }

    final node = program.makeNode(name: name, parent: parent, type: type);
    if (node.id == infoNodes.length) {
      infoNodes.add(node);
    }
    if (index != null) {
      assert(!infoNodeByIndex.containsKey(index));
      infoNodeByIndex[index] = node;
    }
    return node;
  }

  ProgramInfoNode packageOwner(String packageName) =>
      infoNodeForPackage.putIfAbsent(
          packageName,
          () => makeInfoNode(null,
              name: packageName,
              type: NodeType.packageNode,
              parent: program.root));

  /// Create a single key from two node ids.
  /// Note that this operation is commutative, because common ancestor of A and
  /// B is the same as common ancestor of B and A.
  static int ancestorCacheKey(int a, int b) {
    if (a > b) {
      return b << 32 | a;
    } else {
      return a << 32 | b;
    }
  }

  /// Returns id of a common ancestor between [ProgramInfoNode] with [idA] and
  /// [idB].
  int findCommonAncestor(int idA, int idB) {
    if (idA == null) {
      return idB;
    }
    if (idB == null) {
      return idA;
    }
    if (idA == idB) {
      return idA;
    }

    // If either are shared - then result is shared.
    if (idA == ProgramInfo.rootId || idB == ProgramInfo.rootId) {
      return ProgramInfo.rootId;
    }

    final infoA = infoNodes[idA];
    final infoB = infoNodes[idB];

    final key = ancestorCacheKey(idA, idB);
    var ancestor = commonAncestorCache[key];
    if (ancestor == null) {
      commonAncestorCache[key] =
          ancestor = findCommonAncestorImpl(infoA, infoB).id;
    }
    return ancestor;
  }

  static List<ProgramInfoNode> pathToRoot(ProgramInfoNode node) {
    final path = <ProgramInfoNode>[];
    while (node != null) {
      path.add(node);
      node = node.parent;
    }
    return path;
  }

  static ProgramInfoNode findCommonAncestorImpl(
      ProgramInfoNode a, ProgramInfoNode b) {
    final pathA = pathToRoot(a);
    final pathB = pathToRoot(b);
    var i = pathA.length - 1, j = pathB.length - 1;
    while (i > 0 && j > 0 && (pathA[i - 1] == pathB[j - 1])) {
      i--;
      j--;
    }
    assert(pathA[i] == pathB[j]);
    return pathA[i];
  }
}
